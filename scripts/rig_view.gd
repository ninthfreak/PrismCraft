class_name RigView
extends Window

# Rigid ("segmented") skeleton rigging for voxel characters.
#
# Unlike smooth/linear-blend skinning (which blends several bones per vertex
# and smears blocky edges), every voxel here is assigned to EXACTLY ONE bone
# and moves as a solid chunk that pivots about the joint. The silhouette stays
# perfectly crisp — the right model for Minecraft/Crossy-Road-style characters.
#
# Workflow: Load a model -> Auto-Fit Skeleton -> nudge joints -> Rebuild Rig
# -> select a joint and rotate to test the pose -> Export Rigged Scene (.tscn).

const CELL := 1.0

# ─── Humanoid template (index -> name, parent). Root = hips (parent -1). ───
const JOINT_NAMES := [
	"hips", "spine", "chest", "neck", "head",
	"L_shoulder", "L_elbow", "L_wrist",
	"R_shoulder", "R_elbow", "R_wrist",
	"L_hip", "L_knee", "L_ankle",
	"R_hip", "R_knee", "R_ankle",
]
const JOINT_PARENT := [
	-1, 0, 1, 2, 3,
	2, 5, 6,
	2, 8, 9,
	0, 11, 12,
	0, 14, 15,
]

var NJ := JOINT_NAMES.size()

# model
var cells: Array = []
var gx := 0
var gy := 0
var gz := 0
var _solid: PackedByteArray = PackedByteArray()  # flat solidity mask (hot loops)

# skeleton state (cell units / degrees)
var _joint_pos: Array = []   # Array[Vector3]
var _joint_rot: Array = []   # Array[Vector3] euler degrees
var _owner: PackedInt32Array = PackedInt32Array()
var _bb_min: Array = []       # Array[Vector3i] per joint (owned-voxel bbox)
var _bb_max: Array = []       # Array[Vector3i] per joint
var _overlap := 3.0           # socket overlap radius (voxels)
var _color_parts := false     # debug: colour parts by owning bone
var _isolate := false         # debug: light up only the selected bone

# Colourblind-safe qualitative palette (Okabe–Ito).
const OKABE_ITO := [
	Color(0.90, 0.62, 0.00),  # orange
	Color(0.34, 0.71, 0.91),  # sky blue
	Color(0.00, 0.62, 0.45),  # bluish green
	Color(0.94, 0.89, 0.26),  # yellow
	Color(0.00, 0.45, 0.70),  # blue
	Color(0.84, 0.37, 0.00),  # vermillion
	Color(0.80, 0.47, 0.65),  # reddish purple
	Color(0.55, 0.55, 0.55),  # gray
]
var _meshes: Array = []      # Array[ArrayMesh] per joint (may hold null)
var _nodes: Array = []       # Array[Node3D] per joint (preview)
var _markers: Array = []     # Array[MeshInstance3D] per joint (preview)
var _armature: Node3D
var _has_model := false

# ui
var _cam: Camera3D
var _root3d: Node3D
var _mat: ShaderMaterial
var _part_shader: Shader
var _part_mats: Array = []            # Array[ShaderMaterial] per bone (debug tint)
var _mesh_instances: Array = []       # Array[MeshInstance3D] per bone (preview)
var _joint_pick: OptionButton
var _overlap_slider: HSlider
var _overlap_val: Label
var _spin: Array = []        # Array[SpinBox] x/y/z position
var _rot_slider: Array = []  # Array[HSlider] x/y/z rotation
var _rot_val: Array = []     # Array[Label]
var _status: Label
var _open_dialog: FileDialog
var _save_dialog: FileDialog

# orbit camera
var _yaw := -PI / 4.0
var _pitch := PI / 6.0
var _pivot := Vector3.ZERO
var _dist := 20.0
var _rmb := false
var _pan := false

func _init() -> void:
	title = "Rig / Skeleton (rigid — prototype)"
	size = Vector2i(1500, 860)
	min_size = Vector2i(900, 560)
	exclusive = false
	for i in range(NJ):
		_joint_pos.append(Vector3.ZERO)
		_joint_rot.append(Vector3.ZERO)
	_build_material()
	_build_ui()
	close_requested.connect(queue_free)

# ─── Material (matches the compare view's face shading) ───

func _build_material() -> void:
	var sh := Shader.new()
	sh.code = "shader_type spatial;\n" + \
		"render_mode unshaded, cull_disabled;\n" + \
		"void fragment() {\n" + \
		"\tfloat ny = abs(NORMAL.y); float nx = abs(NORMAL.x); float nz = abs(NORMAL.z);\n" + \
		"\tfloat shade = 1.0;\n" + \
		"\tif (ny > 0.9) { shade = NORMAL.y > 0.0 ? 1.0 : 0.5; }\n" + \
		"\telse if (nx > nz) { shade = 0.8; }\n" + \
		"\telse { shade = 0.7; }\n" + \
		"\tALBEDO = COLOR.rgb * shade;\n" + \
		"\tALPHA = COLOR.a;\n" + \
		"\tALPHA_SCISSOR_THRESHOLD = 0.5;\n" + \
		"}\n"
	_mat = ShaderMaterial.new()
	_mat.shader = sh

	# Flat per-bone tint (debug), same face shading so form stays readable.
	var psh := Shader.new()
	psh.code = "shader_type spatial;\n" + \
		"render_mode unshaded, cull_disabled;\n" + \
		"uniform vec4 part_color : source_color = vec4(1.0);\n" + \
		"void fragment() {\n" + \
		"\tfloat ny = abs(NORMAL.y); float nx = abs(NORMAL.x); float nz = abs(NORMAL.z);\n" + \
		"\tfloat shade = 1.0;\n" + \
		"\tif (ny > 0.9) { shade = NORMAL.y > 0.0 ? 1.0 : 0.5; }\n" + \
		"\telse if (nx > nz) { shade = 0.8; }\n" + \
		"\telse { shade = 0.7; }\n" + \
		"\tALBEDO = part_color.rgb * shade;\n" + \
		"\tALPHA = 1.0;\n" + \
		"}\n"
	_part_shader = psh

# ─── UI ───

func _build_ui() -> void:
	var hb := HBoxContainer.new()
	hb.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(hb)

	# left control panel
	var panel := VBoxContainer.new()
	panel.custom_minimum_size = Vector2(300, 0)
	panel.add_theme_constant_override("separation", 6)
	hb.add_child(panel)

	var load_btn := Button.new(); load_btn.text = "Load Model…"
	load_btn.pressed.connect(func(): _open_dialog.popup_centered(Vector2i(760, 520)))
	panel.add_child(load_btn)

	var fit_btn := Button.new(); fit_btn.text = "Auto-Fit Skeleton"
	fit_btn.pressed.connect(_auto_fit)
	panel.add_child(fit_btn)

	panel.add_child(HSeparator.new())

	panel.add_child(_lbl("Joint:"))
	_joint_pick = OptionButton.new()
	for n in JOINT_NAMES:
		_joint_pick.add_item(n)
	_joint_pick.item_selected.connect(_on_joint_selected)
	panel.add_child(_joint_pick)

	panel.add_child(_lbl("Position (voxel units):"))
	var pos_row := HBoxContainer.new()
	panel.add_child(pos_row)
	for axis in range(3):
		var sb := SpinBox.new()
		sb.min_value = 0; sb.max_value = 256; sb.step = 0.5
		sb.custom_minimum_size = Vector2(88, 0)
		sb.value_changed.connect(func(v: float): _on_pos_changed(axis, v))
		pos_row.add_child(sb)
		_spin.append(sb)

	var rebuild_btn := Button.new(); rebuild_btn.text = "Rebuild Rig (re-partition)"
	rebuild_btn.pressed.connect(_rebuild_rig)
	panel.add_child(rebuild_btn)

	panel.add_child(HSeparator.new())

	panel.add_child(_lbl("Joint overlap / socket (voxels):"))
	var orow := HBoxContainer.new()
	panel.add_child(orow)
	_overlap_slider = HSlider.new()
	_overlap_slider.min_value = 0; _overlap_slider.max_value = 12; _overlap_slider.step = 0.5
	_overlap_slider.value = _overlap
	_overlap_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_overlap_slider.value_changed.connect(_on_overlap_value)   # live label
	_overlap_slider.drag_ended.connect(_on_overlap_commit)     # rebuild on release
	orow.add_child(_overlap_slider)
	_overlap_val = Label.new(); _overlap_val.text = str(_overlap); _overlap_val.custom_minimum_size = Vector2(38, 0)
	orow.add_child(_overlap_val)

	var color_chk := CheckBox.new()
	color_chk.text = "Color parts (debug)"
	color_chk.button_pressed = _color_parts
	color_chk.toggled.connect(_on_color_parts_toggled)
	panel.add_child(color_chk)

	var isolate_chk := CheckBox.new()
	isolate_chk.text = "Isolate selected part"
	isolate_chk.button_pressed = _isolate
	isolate_chk.toggled.connect(_on_isolate_toggled)
	panel.add_child(isolate_chk)

	panel.add_child(HSeparator.new())

	panel.add_child(_lbl("Rotate selected joint (deg):"))
	var axis_names := ["X (pitch)", "Y (yaw)", "Z (roll)"]
	for axis in range(3):
		panel.add_child(_lbl(axis_names[axis]))
		var row := HBoxContainer.new()
		panel.add_child(row)
		var sl := HSlider.new()
		sl.min_value = -180; sl.max_value = 180; sl.step = 1
		sl.custom_minimum_size = Vector2(210, 0)
		sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sl.value_changed.connect(func(v: float): _on_rot_changed(axis, v))
		row.add_child(sl)
		_rot_slider.append(sl)
		var vl := Label.new(); vl.text = "0"; vl.custom_minimum_size = Vector2(38, 0)
		row.add_child(vl)
		_rot_val.append(vl)

	var reset_btn := Button.new(); reset_btn.text = "Reset Pose"
	reset_btn.pressed.connect(_reset_pose)
	panel.add_child(reset_btn)

	panel.add_child(HSeparator.new())

	var export_btn := Button.new(); export_btn.text = "Export Rigged Scene (.tscn)…"
	export_btn.pressed.connect(func(): _save_dialog.popup_centered(Vector2i(760, 520)))
	panel.add_child(export_btn)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.text = "Load a model, then Auto-Fit Skeleton."
	panel.add_child(_status)

	# right: 3D view + input overlay
	var view_wrap := Control.new()
	view_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	view_wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hb.add_child(view_wrap)

	var cont := SubViewportContainer.new()
	cont.stretch = true
	cont.set_anchors_preset(Control.PRESET_FULL_RECT)
	cont.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view_wrap.add_child(cont)
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	cont.add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.13, 0.13, 0.17)
	var we := WorldEnvironment.new(); we.environment = env
	vp.add_child(we)
	_cam = Camera3D.new(); vp.add_child(_cam); _cam.current = true
	_root3d = Node3D.new(); vp.add_child(_root3d)
	_armature = Node3D.new(); _armature.name = "Armature"; _root3d.add_child(_armature)

	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.gui_input.connect(_on_view_input)
	view_wrap.add_child(overlay)

	var hint := Label.new()
	hint.text = "Right-drag: rotate  ·  Wheel: zoom  ·  Middle-drag: pan"
	hint.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	hint.position = Vector2(8, -24)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view_wrap.add_child(hint)

	_open_dialog = FileDialog.new()
	_open_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_open_dialog.access = FileDialog.ACCESS_RESOURCES
	_open_dialog.add_filter("*.res, *.tres ; Voxel Definition")
	_open_dialog.current_dir = "res://definitions"
	_open_dialog.file_selected.connect(_load_file)
	add_child(_open_dialog)

	_save_dialog = FileDialog.new()
	_save_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_save_dialog.access = FileDialog.ACCESS_RESOURCES
	_save_dialog.add_filter("*.tscn ; Godot Scene")
	_save_dialog.current_dir = "res://"
	_save_dialog.current_file = "rigged_character.tscn"
	_save_dialog.file_selected.connect(_export_scene)
	add_child(_save_dialog)

func _lbl(t: String) -> Label:
	var l := Label.new(); l.text = t
	return l

# ─── Model loading ───

func _load_file(path: String) -> void:
	if not ResourceLoader.exists(path):
		return
	var def := ResourceLoader.load(path) as VoxelDefinition
	if not def:
		_status.text = "Not a VoxelDefinition: " + path.get_file()
		return
	set_model(def.to_cells(), def.grid_x, def.grid_y, def.grid_z)
	_status.text = "Loaded " + path.get_file() + " (" + str(gx) + "×" + str(gy) + "×" + str(gz) + "). Click Auto-Fit Skeleton."

func set_model(new_cells: Array, ngx: int, ngy: int, ngz: int) -> void:
	cells = new_cells
	gx = ngx; gy = ngy; gz = ngz
	_rebuild_solid_mask()
	_has_model = true
	_pivot = Vector3(gx, gy, gz) * CELL * 0.5
	_dist = maxf(gx, maxf(gy, gz)) * CELL * 1.6
	for sb in _spin:
		sb.max_value = maxi(gx, maxi(gy, gz))
	_update_camera()

func _rebuild_solid_mask() -> void:
	_solid = PackedByteArray()
	_solid.resize(gx * gy * gz)
	for x in range(gx):
		for y in range(gy):
			for z in range(gz):
				if cells[x][y][z][0] != CellTypes.Type.EMPTY:
					_solid[(x * gy + y) * gz + z] = 1

func _is_solid(x: int, y: int, z: int) -> bool:
	return _solid[(x * gy + y) * gz + z] != 0

# ─── Auto-fit: DETECT features (not fixed proportions), so chibi/big-head or
# realistic characters both work. Shoulders = widest row (T-pose arms), neck =
# width pinch above it, hips = where the two legs merge into the torso. ───

func _auto_fit() -> void:
	if not _has_model:
		_status.text = "Load a model first."
		return
	# per-row occupancy stats + z centroid, in one pass
	var width := PackedInt32Array(); width.resize(gy)
	var xmn := PackedInt32Array(); xmn.resize(gy)
	var xmx := PackedInt32Array(); xmx.resize(gy)
	var runs := PackedInt32Array(); runs.resize(gy)
	var ylo := gy; var yhi := -1
	var zsum := 0.0; var zcount := 0
	for y in range(gy):
		var lo := gx; var hi := -1; var r := 0; var prev := false
		for x in range(gx):
			var occ := false
			var base := (x * gy + y) * gz
			for z in range(gz):
				if _solid[base + z] != 0:
					occ = true
					zsum += z; zcount += 1
			if occ:
				lo = mini(lo, x); hi = maxi(hi, x)
				if not prev:
					r += 1
			prev = occ
		if hi >= 0:
			ylo = mini(ylo, y); yhi = maxi(yhi, y)
			width[y] = hi - lo + 1; xmn[y] = lo; xmx[y] = hi; runs[y] = r
	if yhi < 0:
		_status.text = "Model is empty."
		return
	var cz := zsum / maxf(zcount, 1)

	# shoulders: the widest row (T-pose arms make it widest)
	var shoulder_y := ylo
	for y in range(ylo, yhi + 1):
		if width[y] > width[shoulder_y]:
			shoulder_y = y
	var arm_lo := xmn[shoulder_y]
	var arm_hi := xmx[shoulder_y]

	# neck: narrowest row strictly above the shoulders (pinch before the head)
	var neck_y := shoulder_y
	var neck_w := 1 << 30
	for y in range(shoulder_y + 1, yhi + 1):
		if width[y] > 0 and width[y] < neck_w:
			neck_w = width[y]; neck_y = y

	# head centroid: everything above the neck pinch
	var hx := 0.0; var hy := 0.0; var hz := 0.0; var hn := 0
	for x in range(gx):
		for y in range(neck_y + 1, gy):
			var base := (x * gy + y) * gz
			for z in range(gz):
				if _solid[base + z] != 0:
					hx += x; hy += y; hz += z; hn += 1
	var head_cx := (hx / maxf(hn, 1)) if hn > 0 else float((arm_lo + arm_hi)) * 0.5
	var head_cy := (hy / maxf(hn, 1)) if hn > 0 else float(neck_y + 4)
	var head_cz := (hz / maxf(hn, 1)) if hn > 0 else cz

	# hips: highest row (below shoulders) where the legs are still split in two
	var hips_y := ylo + 1
	for y in range(ylo, shoulder_y):
		if runs[y] >= 2:
			hips_y = y
	hips_y = mini(hips_y + 1, shoulder_y - 1)

	var spine_y := int(round((hips_y + shoulder_y) * 0.5))
	var seed_x := int(float(xmn[spine_y] + xmx[spine_y]) * 0.5) if width[spine_y] > 0 else gx / 2
	var trange := _central_x_run(spine_y, seed_x)
	var torso_lo := float(trange.x)
	var torso_hi := float(trange.y)
	var torso_cx := (torso_lo + torso_hi) * 0.5

	# legs: two run centers at mid-leg height
	var leg_y := int(round((ylo + hips_y) * 0.5))
	var legs := _two_runs(leg_y)
	var lleg_x := legs.x
	var rleg_x := legs.y

	var ankle_y := float(ylo + 1)
	var knee_y := (ankle_y + hips_y) * 0.5

	_joint_pos[0]  = Vector3(torso_cx, hips_y, cz)                    # hips
	_joint_pos[1]  = Vector3(torso_cx, spine_y, cz)                   # spine
	_joint_pos[2]  = Vector3(torso_cx, shoulder_y, cz)               # chest
	_joint_pos[3]  = Vector3(torso_cx, neck_y, cz)                    # neck (head pivot)
	_joint_pos[4]  = Vector3(head_cx, head_cy, head_cz)              # head (endpoint)
	_joint_pos[5]  = Vector3(torso_lo, shoulder_y, cz)               # L_shoulder
	_joint_pos[6]  = Vector3((torso_lo + arm_lo) * 0.5, shoulder_y, cz)  # L_elbow
	_joint_pos[7]  = Vector3(arm_lo, shoulder_y, cz)                 # L_wrist (endpoint)
	_joint_pos[8]  = Vector3(torso_hi, shoulder_y, cz)               # R_shoulder
	_joint_pos[9]  = Vector3((torso_hi + arm_hi) * 0.5, shoulder_y, cz)  # R_elbow
	_joint_pos[10] = Vector3(arm_hi, shoulder_y, cz)                 # R_wrist (endpoint)
	_joint_pos[11] = Vector3(lleg_x, hips_y, cz)                     # L_hip
	_joint_pos[12] = Vector3(lleg_x, knee_y, cz)                     # L_knee
	_joint_pos[13] = Vector3(lleg_x, ankle_y, cz)                    # L_ankle (endpoint)
	_joint_pos[14] = Vector3(rleg_x, hips_y, cz)                     # R_hip
	_joint_pos[15] = Vector3(rleg_x, knee_y, cz)                     # R_knee
	_joint_pos[16] = Vector3(rleg_x, ankle_y, cz)                    # R_ankle (endpoint)

	for i in range(NJ):
		_joint_rot[i] = Vector3.ZERO
	_rebuild_rig()
	_on_joint_selected(_joint_pick.selected)
	_status.text = "Skeleton fitted (shoulders y=%d, neck y=%d, hips y=%d). Nudge joints + Rebuild, or rotate to test." % [shoulder_y, neck_y, hips_y]

# occupancy helpers -------------------------------------------------------

func _solid_col_at(x: int, y: int) -> bool:
	if x < 0 or x >= gx or y < 0 or y >= gy:
		return false
	var base := (x * gy + y) * gz
	for z in range(gz):
		if _solid[base + z] != 0:
			return true
	return false

func _central_x_run(y: int, seed_x: int) -> Vector2i:
	var lo := clampi(seed_x, 0, gx - 1)
	var hi := lo
	if not _solid_col_at(lo, y):
		# find any solid near center
		var found := false
		for d in range(gx):
			if _solid_col_at(clampi(seed_x + d, 0, gx - 1), y):
				lo = clampi(seed_x + d, 0, gx - 1); hi = lo; found = true; break
			if _solid_col_at(clampi(seed_x - d, 0, gx - 1), y):
				lo = clampi(seed_x - d, 0, gx - 1); hi = lo; found = true; break
		if not found:
			return Vector2i(seed_x, seed_x)
	while lo - 1 >= 0 and _solid_col_at(lo - 1, y):
		lo -= 1
	while hi + 1 < gx and _solid_col_at(hi + 1, y):
		hi += 1
	return Vector2i(lo, hi)

func _two_runs(y: int) -> Vector2:
	# centers of the two widest separate X-runs (the legs)
	var runs: Array = []
	var s := -1
	for x in range(gx):
		var occ := _solid_col_at(x, y)
		if occ and s < 0:
			s = x
		elif not occ and s >= 0:
			runs.append(Vector2(s, x - 1)); s = -1
	if s >= 0:
		runs.append(Vector2(s, gx - 1))
	if runs.size() >= 2:
		runs.sort_custom(func(a, b): return (a.y - a.x) > (b.y - b.x))
		var a: Vector2 = runs[0]; var b: Vector2 = runs[1]
		var ca := (a.x + a.y) * 0.5; var cb := (b.x + b.y) * 0.5
		return Vector2(minf(ca, cb), maxf(ca, cb))
	var c := gx * 0.5
	return Vector2(c - gx * 0.12, c + gx * 0.12)

# ─── Rigid partition + mesh build ───

func _rebuild_rig() -> void:
	if not _has_model:
		return
	_owner = _compute_owner()  # also fills _bb_min / _bb_max
	_rebuild_meshes()

# Rebuild only the meshes (reusing the cached partition). Used when the socket
# overlap or part-colour toggle changes — no need to re-partition.
func _rebuild_meshes() -> void:
	if _owner.is_empty():
		return
	_meshes = _build_owner_meshes(_owner)
	_build_hierarchy_preview()
	_apply_pose()

func _on_overlap_value(v: float) -> void:
	_overlap = v
	_overlap_val.text = str(v)

func _on_overlap_commit(_value_changed: bool) -> void:
	if _has_model and not _owner.is_empty():
		_rebuild_meshes()

func _on_color_parts_toggled(on: bool) -> void:
	_color_parts = on
	_apply_debug_colors()

func _on_isolate_toggled(on: bool) -> void:
	_isolate = on
	_apply_debug_colors()

# Debug tinting via per-bone material overrides — instant, no mesh rebuild.
# "Isolate" lights the selected bone white and greys the rest (colourblind-safe).
func _apply_debug_colors() -> void:
	if _mesh_instances.is_empty():
		return
	if _part_mats.size() != NJ:
		_part_mats = []
		for j in range(NJ):
			var m := ShaderMaterial.new()
			m.shader = _part_shader
			_part_mats.append(m)
	var sel := _joint_pick.selected
	for j in range(_mesh_instances.size()):
		var mi: MeshInstance3D = _mesh_instances[j]
		if mi == null:
			continue
		if not _color_parts:
			mi.material_override = null
			continue
		var col: Color
		if _isolate:
			col = Color(1, 1, 1) if j == sel else Color(0.26, 0.26, 0.30)
		else:
			col = OKABE_ITO[j % OKABE_ITO.size()]
		var mat: ShaderMaterial = _part_mats[j]
		mat.set_shader_parameter("part_color", col)
		mi.material_override = mat

func _dist_point_seg(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var denom := ab.length_squared()
	var t := 0.0
	if denom > 0.0:
		t = clampf((p - a).dot(ab) / denom, 0.0, 1.0)
	return p.distance_to(a + ab * t)

func _compute_owner() -> PackedInt32Array:
	var owner := PackedInt32Array()
	owner.resize(gx * gy * gz)
	_bb_min = []
	_bb_max = []
	for j in range(NJ):
		_bb_min.append(Vector3i(gx, gy, gz))
		_bb_max.append(Vector3i(-1, -1, -1))
	# segments: [parent_joint, a, b] — voxel owned by the segment's parent (pivot)
	var segs: Array = []
	for j in range(NJ):
		var p: int = JOINT_PARENT[j]
		if p < 0:
			continue
		segs.append([p, _joint_pos[p], _joint_pos[j]])
	for x in range(gx):
		for y in range(gy):
			for z in range(gz):
				var idx := (x * gy + y) * gz + z
				if _solid[idx] == 0:
					owner[idx] = -1
					continue
				var pt := Vector3(x + 0.5, y + 0.5, z + 0.5)
				var best := INF
				var best_owner := 0
				for s in segs:
					var d: float = _dist_point_seg(pt, s[1], s[2])
					if d < best:
						best = d
						best_owner = s[0]
				owner[idx] = best_owner
				var bmn: Vector3i = _bb_min[best_owner]
				var bmx: Vector3i = _bb_max[best_owner]
				_bb_min[best_owner] = Vector3i(mini(bmn.x, x), mini(bmn.y, y), mini(bmn.z, z))
				_bb_max[best_owner] = Vector3i(maxi(bmx.x, x), maxi(bmx.y, y), maxi(bmx.z, z))
	return owner

func _build_owner_meshes(owner: PackedInt32Array) -> Array:
	var dirs := [
		[Vector3i(0, 1, 0), CellTypes.FACE_TOP, Vector3(0, 1, 0)],
		[Vector3i(0, -1, 0), CellTypes.FACE_BOTTOM, Vector3(0, -1, 0)],
		[Vector3i(1, 0, 0), CellTypes.FACE_RIGHT, Vector3(1, 0, 0)],
		[Vector3i(-1, 0, 0), CellTypes.FACE_LEFT, Vector3(-1, 0, 0)],
		[Vector3i(0, 0, 1), CellTypes.FACE_FRONT, Vector3(0, 0, 1)],
		[Vector3i(0, 0, -1), CellTypes.FACE_BACK, Vector3(0, 0, -1)],
	]
	var s := CELL
	var quads := [
		[Vector3(0, s, 0), Vector3(s, s, 0), Vector3(s, s, s), Vector3(0, s, s)],
		[Vector3(0, 0, s), Vector3(s, 0, s), Vector3(s, 0, 0), Vector3(0, 0, 0)],
		[Vector3(s, 0, 0), Vector3(s, s, 0), Vector3(s, s, s), Vector3(s, 0, s)],
		[Vector3(0, 0, s), Vector3(0, s, s), Vector3(0, s, 0), Vector3(0, 0, 0)],
		[Vector3(0, 0, s), Vector3(0, s, s), Vector3(s, s, s), Vector3(s, 0, s)],
		[Vector3(s, 0, 0), Vector3(s, s, 0), Vector3(0, s, 0), Vector3(0, 0, 0)],
	]
	var r2 := _overlap * _overlap
	var rr := int(ceil(_overlap))
	var meshes: Array = []
	meshes.resize(NJ)

	# Mesh each bone from its own region. A bone's part is its owned voxels PLUS
	# (socket overlap) a ball of the parent's voxels around the joint, duplicated
	# in so a rotation keeps the joint covered instead of tearing a gap.
	for c in range(NJ):
		var bmn: Vector3i = _bb_min[c]
		var bmx: Vector3i = _bb_max[c]
		if bmx.x < 0:
			meshes[c] = null  # bone owns no voxels
			continue
		var pc: int = JOINT_PARENT[c]
		var cpos: Vector3 = _joint_pos[c]
		# region covers the owned bbox AND the overlap ball around the joint
		var cix := int(cpos.x); var ciy := int(cpos.y); var ciz := int(cpos.z)
		var x0 := maxi(0, mini(bmn.x, cix) - rr); var x1 := mini(gx - 1, maxi(bmx.x, cix) + rr)
		var y0 := maxi(0, mini(bmn.y, ciy) - rr); var y1 := mini(gy - 1, maxi(bmx.y, ciy) + rr)
		var z0 := maxi(0, mini(bmn.z, ciz) - rr); var z1 := mini(gz - 1, maxi(bmx.z, ciz) + rr)
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var used := false
		for x in range(x0, x1 + 1):
			for y in range(y0, y1 + 1):
				for z in range(z0, z1 + 1):
					if not _voxel_in_part(x, y, z, c, pc, cpos, r2, owner):
						continue
					var cell: Array = cells[x][y][z]
					var origin := Vector3(x, y, z) * CELL - cpos * CELL
					for i in range(6):
						var d: Array = dirs[i]
						var fv: int = cell[d[1]]
						var col := CellTypes.decode_color(fv)
						if CellTypes.is_rgb5551(fv) and col.a < CellTypes.ALPHA_THRESHOLD:
							continue
						var nrm: Vector3i = d[0]
						var nx := x + nrm.x; var ny := y + nrm.y; var nz := z + nrm.z
						if nx >= 0 and nx < gx and ny >= 0 and ny < gy and nz >= 0 and nz < gz:
							# cull faces shared with a solid neighbour in the SAME part;
							# seams against other bones stay drawn (closed shell).
							if _voxel_in_part(nx, ny, nz, c, pc, cpos, r2, owner):
								continue
						var q: Array = quads[i]
						var normal: Vector3 = d[2]
						_add_quad(st, origin + q[0], origin + q[1], origin + q[2], origin + q[3], normal, col)
						used = true
		meshes[c] = st.commit() if used else null
	return meshes

# Is voxel (x,y,z) part of bone c? True if c owns it, or (socket overlap) it is
# a parent-owned voxel within the overlap radius of c's joint.
func _voxel_in_part(x: int, y: int, z: int, c: int, pc: int, cpos: Vector3, r2: float, owner: PackedInt32Array) -> bool:
	var idx := (x * gy + y) * gz + z
	if _solid[idx] == 0:
		return false
	var o: int = owner[idx]
	if o == c:
		return true
	if pc >= 0 and o == pc and r2 > 0.0:
		var dx := (x + 0.5) - cpos.x
		var dy := (y + 0.5) - cpos.y
		var dz := (z + 0.5) - cpos.z
		if dx * dx + dy * dy + dz * dz <= r2:
			return true
	return false

func _add_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3, color: Color) -> void:
	_add_tri(st, a, b, c, normal, color)
	_add_tri(st, a, c, d, normal, color)

func _add_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, normal: Vector3, color: Color) -> void:
	st.set_normal(normal)
	st.set_color(color)
	var cp := (b - a).cross(c - a)
	if cp.dot(normal) < 0:
		st.add_vertex(a); st.add_vertex(b); st.add_vertex(c)
	else:
		st.add_vertex(a); st.add_vertex(c); st.add_vertex(b)

# ─── Preview hierarchy (Node3D pivots) ───

func _build_hierarchy_preview() -> void:
	for c in _armature.get_children():
		_armature.remove_child(c)
		c.queue_free()
	_nodes = []
	_markers = []
	_mesh_instances = []
	_nodes.resize(NJ)
	_markers.resize(NJ)
	_mesh_instances.resize(NJ)
	# parents always precede children in the template, so a single pass works.
	for j in range(NJ):
		var node := Node3D.new()
		node.name = JOINT_NAMES[j]
		var p: int = JOINT_PARENT[j]
		var local: Vector3
		if p < 0:
			local = _joint_pos[j] * CELL
			_armature.add_child(node)
		else:
			local = (_joint_pos[j] - _joint_pos[p]) * CELL
			(_nodes[p] as Node3D).add_child(node)
		node.position = local
		_nodes[j] = node

		if _meshes[j] != null:
			var mi := MeshInstance3D.new()
			mi.name = JOINT_NAMES[j] + "_mesh"
			mi.mesh = _meshes[j]
			for si in range((_meshes[j] as ArrayMesh).get_surface_count()):
				mi.set_surface_override_material(si, _mat)
			node.add_child(mi)
			_mesh_instances[j] = mi

		# joint marker
		var mk := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3.ONE * CELL * 2.2
		mk.mesh = bm
		var mkmat := StandardMaterial3D.new()
		mkmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mkmat.albedo_color = Color(0.2, 0.8, 1.0)
		mk.material_override = mkmat
		node.add_child(mk)
		_markers[j] = mk
	_highlight(_joint_pick.selected)
	_apply_debug_colors()

func _highlight(sel: int) -> void:
	for j in range(_markers.size()):
		var mk: MeshInstance3D = _markers[j]
		if mk == null:
			continue
		var m := mk.material_override as StandardMaterial3D
		if m:
			m.albedo_color = Color(1.0, 0.85, 0.15) if j == sel else Color(0.2, 0.8, 1.0)

func _apply_pose() -> void:
	for j in range(_nodes.size()):
		var node: Node3D = _nodes[j]
		if node == null:
			continue
		var e: Vector3 = _joint_rot[j]
		node.rotation = Vector3(deg_to_rad(e.x), deg_to_rad(e.y), deg_to_rad(e.z))

# ─── UI callbacks ───

func _on_joint_selected(idx: int) -> void:
	if idx < 0 or idx >= NJ:
		return
	var p: Vector3 = _joint_pos[idx]
	_spin[0].set_value_no_signal(p.x)
	_spin[1].set_value_no_signal(p.y)
	_spin[2].set_value_no_signal(p.z)
	var r: Vector3 = _joint_rot[idx]
	_rot_slider[0].set_value_no_signal(r.x); _rot_val[0].text = str(int(r.x))
	_rot_slider[1].set_value_no_signal(r.y); _rot_val[1].text = str(int(r.y))
	_rot_slider[2].set_value_no_signal(r.z); _rot_val[2].text = str(int(r.z))
	_highlight(idx)
	_apply_debug_colors()

func _on_pos_changed(axis: int, v: float) -> void:
	var idx := _joint_pick.selected
	if idx < 0:
		return
	var p: Vector3 = _joint_pos[idx]
	p[axis] = v
	_joint_pos[idx] = p
	# move the marker live; meshes re-partition on Rebuild Rig
	if idx < _nodes.size() and _nodes[idx] != null:
		var node: Node3D = _nodes[idx]
		var par: int = JOINT_PARENT[idx]
		if par < 0:
			node.position = p * CELL
		else:
			node.position = (p - _joint_pos[par]) * CELL

func _on_rot_changed(axis: int, v: float) -> void:
	var idx := _joint_pick.selected
	if idx < 0:
		return
	var r: Vector3 = _joint_rot[idx]
	r[axis] = v
	_joint_rot[idx] = r
	_rot_val[axis].text = str(int(v))
	if idx < _nodes.size() and _nodes[idx] != null:
		var node: Node3D = _nodes[idx]
		node.rotation = Vector3(deg_to_rad(r.x), deg_to_rad(r.y), deg_to_rad(r.z))

func _reset_pose() -> void:
	for i in range(NJ):
		_joint_rot[i] = Vector3.ZERO
	_apply_pose()
	_on_joint_selected(_joint_pick.selected)

# ─── Export ───

func _export_scene(path: String) -> void:
	if not _has_model or _owner.is_empty():
		_status.text = "Build the rig first (Auto-Fit)."
		return
	# Fresh rest-pose hierarchy (rotations zero) with the part meshes.
	var root := Node3D.new()
	root.name = "RiggedCharacter"
	var nodes: Array = []
	nodes.resize(NJ)
	for j in range(NJ):
		var node := Node3D.new()
		node.name = JOINT_NAMES[j]
		var p: int = JOINT_PARENT[j]
		if p < 0:
			node.position = _joint_pos[j] * CELL
			root.add_child(node)
		else:
			node.position = (_joint_pos[j] - _joint_pos[p]) * CELL
			(nodes[p] as Node3D).add_child(node)
		nodes[j] = node
		if _meshes[j] != null:
			var mi := MeshInstance3D.new()
			mi.name = JOINT_NAMES[j] + "_mesh"
			mi.mesh = _meshes[j]
			node.add_child(mi)
	var anim := AnimationPlayer.new()
	anim.name = "AnimationPlayer"
	root.add_child(anim)

	_set_owner(root, root)
	var ps := PackedScene.new()
	var err := ps.pack(root)
	if err != OK:
		_status.text = "Pack failed (err %d)." % err
		root.queue_free()
		return
	err = ResourceSaver.save(ps, path)
	root.queue_free()
	if err == OK:
		_status.text = "Exported " + path.get_file() + ". Open it in Godot and key joint rotations in the AnimationPlayer."
	else:
		_status.text = "Save failed (err %d)." % err

func _set_owner(node: Node, owner: Node) -> void:
	for c in node.get_children():
		if c != owner:
			c.owner = owner
		_set_owner(c, owner)

# ─── Camera ───

func _update_camera() -> void:
	var offset := Vector3(sin(_yaw) * cos(_pitch), sin(_pitch), cos(_yaw) * cos(_pitch)) * _dist
	_cam.position = _pivot + offset
	_cam.look_at(_pivot, Vector3.UP)

func _on_view_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_RIGHT:
				_rmb = event.pressed
			MOUSE_BUTTON_MIDDLE:
				_pan = event.pressed
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed:
					_dist = maxf(0.5, _dist * 0.9); _update_camera()
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					_dist *= 1.1; _update_camera()
	elif event is InputEventMouseMotion:
		if _rmb:
			_yaw -= event.relative.x * 0.01
			_pitch = clampf(_pitch + event.relative.y * 0.01, -PI * 0.49, PI * 0.49)
			_update_camera()
		elif _pan:
			var b := _cam.global_transform.basis
			var delta: Vector3 = (-b.x * event.relative.x + b.y * event.relative.y) * (_dist * 0.0025)
			_pivot += delta
			_update_camera()
