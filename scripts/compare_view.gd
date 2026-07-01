class_name CompareView
extends Window

# Side-by-side, view-only comparison of two voxel models.
# Camera orbit / zoom / pan is applied to BOTH views simultaneously.

const CELL := 1.0

var _camA: Camera3D
var _camB: Camera3D
var _rootA: Node3D
var _rootB: Node3D
var _labelA: Label
var _labelB: Label
var _file_dialog: FileDialog
var _pick_slot := 1

var _mat: ShaderMaterial

# shared orbit state
var _yaw := -PI / 4.0
var _pitch := PI / 6.0
var _pivotA := Vector3.ZERO
var _pivotB := Vector3.ZERO
var _distA := 15.0
var _distB := 15.0
var _rmb := false
var _pan := false

func _init() -> void:
	title = "Compare Models (view only)"
	size = Vector2i(1400, 820)
	min_size = Vector2i(800, 500)
	exclusive = false
	_build_material()
	_build_ui()
	close_requested.connect(queue_free)

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

func _build_ui() -> void:
	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(vb)

	# top bar
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	vb.add_child(top)
	var btnA := Button.new(); btnA.text = "Load Left…"
	btnA.pressed.connect(func(): _pick(1)); top.add_child(btnA)
	_labelA = Label.new(); _labelA.text = "Left: (none)"; top.add_child(_labelA)
	top.add_child(VSeparator.new())
	var btnB := Button.new(); btnB.text = "Load Right…"
	btnB.pressed.connect(func(): _pick(2)); top.add_child(btnB)
	_labelB = Label.new(); _labelB.text = "Right: (none)"; top.add_child(_labelB)
	top.add_child(VSeparator.new())
	var reset := Button.new(); reset.text = "Reset View"
	reset.pressed.connect(_reset_view); top.add_child(reset)

	# content: two viewports + input overlay
	var content := Control.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(content)

	var hb := HBoxContainer.new()
	hb.set_anchors_preset(Control.PRESET_FULL_RECT)
	hb.add_theme_constant_override("separation", 4)
	content.add_child(hb)
	_rootA = Node3D.new(); _camA = Camera3D.new()
	_make_view(hb, _camA, _rootA)
	_rootB = Node3D.new(); _camB = Camera3D.new()
	_make_view(hb, _camB, _rootB)

	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.gui_input.connect(_on_view_input)
	content.add_child(overlay)

	var hint := Label.new()
	hint.text = "  Right-drag: rotate both  ·  Wheel: zoom both  ·  Middle-drag: pan both  ·  view only, no editing"
	vb.add_child(hint)

	_file_dialog = FileDialog.new()
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.access = FileDialog.ACCESS_RESOURCES
	_file_dialog.add_filter("*.res, *.tres ; Voxel Definition")
	_file_dialog.current_dir = "res://definitions"
	_file_dialog.file_selected.connect(_on_file_selected)
	add_child(_file_dialog)

func _make_view(parent: Control, cam: Camera3D, root: Node3D) -> void:
	var cont := SubViewportContainer.new()
	cont.stretch = true
	cont.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cont.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cont.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(cont)
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	cont.add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.15, 0.15, 0.2)
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	vp.add_child(cam)
	cam.current = true
	vp.add_child(root)

func _pick(slot: int) -> void:
	_pick_slot = slot
	_file_dialog.popup_centered(Vector2i(760, 520))

func _on_file_selected(path: String) -> void:
	load_file(_pick_slot, path)

func load_file(slot: int, path: String) -> void:
	if not ResourceLoader.exists(path):
		return
	var def := ResourceLoader.load(path) as VoxelDefinition
	if not def:
		return
	load_cells(slot, def.to_cells(), def.grid_x, def.grid_y, def.grid_z, path.get_file())

func load_cells(slot: int, cells: Array, gx: int, gy: int, gz: int, disp: String) -> void:
	var root := _rootA if slot == 1 else _rootB
	for c in root.get_children():
		c.queue_free()
	var mesh := BlockMeshBuilder.build_mesh(cells, gx, gy, gz, CELL)
	if mesh and mesh.get_surface_count() > 0:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		for si in range(mesh.get_surface_count()):
			mi.set_surface_override_material(si, _mat)
		root.add_child(mi)
	var center := Vector3(gx, gy, gz) * CELL * 0.5
	var dist: float = max(gx, max(gy, gz)) * CELL * 1.4
	if slot == 1:
		_pivotA = center; _distA = dist
		_labelA.text = "Left: " + disp
	else:
		_pivotB = center; _distB = dist
		_labelB.text = "Right: " + disp
	_update_cameras()

func _reset_view() -> void:
	_yaw = -PI / 4.0
	_pitch = PI / 6.0
	_update_cameras()

func _update_cameras() -> void:
	_apply_cam(_camA, _pivotA, _distA)
	_apply_cam(_camB, _pivotB, _distB)

func _apply_cam(cam: Camera3D, pivot: Vector3, dist: float) -> void:
	var offset := Vector3(sin(_yaw) * cos(_pitch), sin(_pitch), cos(_yaw) * cos(_pitch)) * dist
	cam.position = pivot + offset
	cam.look_at(pivot, Vector3.UP)

func _on_view_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_RIGHT:
				_rmb = event.pressed
			MOUSE_BUTTON_MIDDLE:
				_pan = event.pressed
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed:
					_distA = maxf(0.5, _distA * 0.9)
					_distB = maxf(0.5, _distB * 0.9)
					_update_cameras()
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					_distA *= 1.1
					_distB *= 1.1
					_update_cameras()
	elif event is InputEventMouseMotion:
		if _rmb:
			_yaw -= event.relative.x * 0.01
			_pitch = clampf(_pitch + event.relative.y * 0.01, -PI * 0.49, PI * 0.49)
			_update_cameras()
		elif _pan:
			var b := _camA.global_transform.basis
			var delta: Vector3 = (-b.x * event.relative.x + b.y * event.relative.y) * (_distA * 0.0025)
			_pivotA += delta
			_pivotB += delta
			_update_cameras()
