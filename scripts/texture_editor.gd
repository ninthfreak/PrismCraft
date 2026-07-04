class_name TextureEditor
extends Window

# Atlas-aware block texture editor. Pick a shape and the canvas is created at
# the exact size the importer demands, with every atlas region outlined and
# labeled — format-correct by construction, no more 1:1 rejections. Painting
# rebuilds the block through the real import path (BlockImporter) into a live
# 3D preview. Round-trips plain PNGs, so external pixel editors stay usable.

const GX := 32
const CELL := 1.0

# Emitted when the user explicitly picks a shape, so the editor can remember the
# corrected layout on the model (persisted on save) instead of guessing again.
signal layout_chosen(layout: String)

const TOOL_PENCIL := 0
const TOOL_FILL := 1
const TOOL_ERASE := 2
const TOOL_EYEDROP := 3

var _layout := "uniform"
# The model this editor is bound to, kept so switching the shape re-derives the
# atlas from the same voxels instead of blanking the canvas.
var _model_cells: Array = []
var _model_gx := 32
var _model_gy := 32
var _model_gz := 32
var _img: Image
var _tex: ImageTexture
var _regions: Array = []
var _zoom := 8
var _color := Color(0.62, 0.58, 0.52)
var _tool := TOOL_PENCIL
var _show_regions := true
var _undo_stack: Array = []
var _last_px := Vector2i(-1, -1)
var _painting := false

var _canvas: PixelCanvas
var _shape_pick: OptionButton
var _zoom_pick: OptionButton
var _name_edit: LineEdit
var _color_btn: ColorPickerButton
var _tool_btns: Array = []
var _status: Label
var _size_lbl: Label
var _save_dialog: FileDialog
var _load_dialog: FileDialog
var _preview_timer: Timer

# 3D preview
var _cam: Camera3D
var _proot: Node3D
var _pmat: ShaderMaterial
var _yaw := -PI / 4.0
var _pitch := PI / 6.0
var _pivot := Vector3(16, 16, 16)
var _dist := 55.0
var _rmb := false
var _pan := false

# ─── format + region tables ──────────────────────────────────────────────────
# [layout, shape_token, width, height] — sizes match validate_block_texture.
static func formats() -> Array:
	return [
		["uniform", "cube", 32, 32],
		["capped", "capped", 64, 32],
		["net", "net", 96, 64],
		["octagon_full", "octagon", CellTypes.octagon_atlas_width(32), 32],
		["octagon_half", "octagon-half", CellTypes.octagon_atlas_width(16), 32],
		["diamond", "diamond", 96, 32],
		["chamfered", "chamfered", 144, 32],
		["cross", "cross", 160, 32],
		["ramp", "ramp", 128, 64],
		["gable", "gable", 128, 48],
		["diagwall", "diagwall", 112, 32],
		["opening", "opening", 224, 32],
		["panel", "panel", 64, 34],
		["slab_quarter", "slab-quarter", 64, 48],
		["slab_half", "slab-half", 64, 64],
		["stairs_2", "stairs-2", 128, 32],
		["stairs_4", "stairs-4", 80, 64],
		["pipe_quarter", "pipe-quarter", 120, 32],
	]

static func _r(n: String, x: int, y: int, w: int, h: int) -> Dictionary:
	return {"name": n, "rect": Rect2i(x, y, w, h)}

static func _strip(labels: Array, widths: Array, h: int, x0: int = 0) -> Array:
	var out: Array = []
	var col := x0
	for i in range(labels.size()):
		var w: int = widths[i]
		out.append(_r(labels[i], col, 0, w, h))
		col += w
	return out

static func _oct_regions(fp: int) -> Array:
	var c := CellTypes.octagon_chamfer(fp)
	var aw := fp - 2 * c
	var out := _strip(["E", "NE", "N", "NW", "W", "SW", "S", "SE"],
		[aw, c, aw, c, aw, c, aw, c], 32)
	out.append(_r("cap", CellTypes.octagon_strip_width(fp), 0, fp, fp))
	if fp < 32:
		out.append(_r("unused", CellTypes.octagon_strip_width(fp), fp, fp, 32 - fp))
	return out

static func regions_for(layout: String) -> Array:
	var F := 32
	match layout:
		"uniform":
			return [_r("all faces", 0, 0, F, F)]
		"capped":
			return [_r("sides", 0, 0, F, F), _r("top+bottom cap", F, 0, F, F)]
		"net":
			return [_r("top", 0, 0, F, F), _r("front", F, 0, F, F), _r("right", F * 2, 0, F, F),
				_r("bottom", 0, F, F, F), _r("back", F, F, F, F), _r("left", F * 2, F, F, F)]
		"octagon_full":
			return _oct_regions(32)
		"octagon_half":
			return _oct_regions(16)
		"diamond":
			return _strip(["NE", "NW", "SW", "SE"], [16, 16, 16, 16], F) + [_r("cap", 64, 0, F, F)]
		"chamfered":
			return _strip(["E", "NE", "N", "NW", "W", "SW", "S", "SE"],
				[24, 4, 24, 4, 24, 4, 24, 4], F) + [_r("cap", 112, 0, F, F)]
		"cross":
			return _strip(["E end", "E s", "S e", "S end", "S w", "W s", "W end", "W n", "N w", "N end", "N e", "E n"],
				[16, 8, 8, 16, 8, 8, 16, 8, 8, 16, 8, 8], F) + [_r("cap", 128, 0, F, F)]
		"ramp":
			return [_r("slope", 0, 0, F, F), _r("back", F, 0, F, F), _r("bottom", F * 2, 0, F, F),
				_r("unused", F * 3, 0, F, F), _r("side L", 0, F, F, F), _r("side R", F, F, F, F),
				_r("unused", F * 2, F, F * 2, F)]
		"gable":
			return [_r("slope A", 0, 0, F, 16), _r("slope B", F, 0, F, 16), _r("end A", F * 2, 0, F, 16),
				_r("end B", F * 3, 0, F, 16), _r("bottom", 0, 16, F, F), _r("unused", F, 16, F * 3, F)]
		"diagwall":
			return [_r("wall A (SE)", 0, 0, F, F), _r("wall B (NW)", F, 0, F, F),
				_r("end A (SW)", 64, 0, 8, F), _r("end B (NE)", 72, 0, 8, F),
				_r("ribbon top", 80, 0, F, 8), _r("ribbon bottom", 80, 8, F, 8),
				_r("unused", 80, 16, F, 16)]
		"opening":
			return [_r("front", 0, 0, F, 24), _r("unused", 0, 24, F, 8),
				_r("chamfer", F, 0, F, 8), _r("unused", F, 8, F, 24),
				_r("top", F * 2, 0, F, 24), _r("unused", F * 2, 24, F, 8),
				_r("back", F * 3, 0, F, F), _r("bottom", F * 4, 0, F, F),
				_r("side L", F * 5, 0, F, F), _r("side R", F * 6, 0, F, F)]
		"panel":
			return [_r("top", 0, 0, F, F), _r("bottom", F, 0, F, F),
				_r("N", 0, 32, F, 1), _r("S", F, 32, F, 1), _r("E", 0, 33, F, 1), _r("W", F, 33, F, 1)]
		"slab_quarter":
			return [_r("top", 0, 0, F, F), _r("bottom", F, 0, F, F),
				_r("N", 0, 32, F, 8), _r("S", F, 32, F, 8), _r("E", 0, 40, F, 8), _r("W", F, 40, F, 8)]
		"slab_half":
			return [_r("top", 0, 0, F, F), _r("bottom", F, 0, F, F),
				_r("N", 0, 32, F, 16), _r("S", F, 32, F, 16), _r("E", 0, 48, F, 16), _r("W", F, 48, F, 16)]
		"stairs_2":
			return [_r("tread", 0, 0, 16, F), _r("riser", 16, 0, 16, F), _r("back", 32, 0, F, F),
				_r("bottom", 64, 0, F, F), _r("side", 96, 0, F, F)]
		"stairs_4":
			return [_r("tread", 0, 0, 8, F), _r("riser", 8, 0, 8, F), _r("back", 16, 0, F, F),
				_r("bottom", 48, 0, F, F), _r("side", 0, 32, F, F), _r("unused", 32, 32, 48, F)]
		"pipe_quarter":
			return [_r("outer arc", 0, 0, 45, F), _r("inner arc", 45, 0, 41, F),
				_r("end ring", 86, 0, F, F), _r("cut", 118, 0, 2, F)]
	return []

# ─── window setup ────────────────────────────────────────────────────────────
func _init() -> void:
	title = "Texture Editor"
	size = Vector2i(1500, 860)
	min_size = Vector2i(1000, 600)
	exclusive = false
	_build_preview_material()
	_build_ui()
	close_requested.connect(queue_free)
	_new_canvas("uniform")

func _build_preview_material() -> void:
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
	_pmat = ShaderMaterial.new()
	_pmat.shader = sh

func _build_ui() -> void:
	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(vb)

	# ── top bar ──
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	vb.add_child(top)

	top.add_child(_lbl("Shape"))
	_shape_pick = OptionButton.new()
	for f in formats():
		_shape_pick.add_item("%s  (%dx%d)" % [f[1], f[2], f[3]])
	_shape_pick.item_selected.connect(_on_shape_selected)
	top.add_child(_shape_pick)

	var new_btn := Button.new(); new_btn.text = "New"
	new_btn.pressed.connect(func(): _new_canvas(_layout))
	top.add_child(new_btn)
	var load_btn := Button.new(); load_btn.text = "Load…"
	load_btn.pressed.connect(func(): _load_dialog.popup_centered(Vector2i(760, 520)))
	top.add_child(load_btn)
	var save_btn := Button.new(); save_btn.text = "Save…"
	save_btn.pressed.connect(_on_save_pressed)
	top.add_child(save_btn)

	top.add_child(VSeparator.new())
	top.add_child(_lbl("Name"))
	_name_edit = LineEdit.new()
	_name_edit.text = "material"
	_name_edit.custom_minimum_size = Vector2(170, 0)
	_name_edit.tooltip_text = "material-variant field for the filename (hyphens inside, e.g. stone-block)"
	top.add_child(_name_edit)

	top.add_child(VSeparator.new())
	_color_btn = ColorPickerButton.new()
	_color_btn.color = _color
	_color_btn.edit_alpha = false
	_color_btn.custom_minimum_size = Vector2(46, 0)
	_color_btn.color_changed.connect(func(c: Color): _color = c)
	top.add_child(_color_btn)

	var tool_group := ButtonGroup.new()
	var tool_names := ["Pencil", "Fill", "Erase", "Eyedrop"]
	for i in range(tool_names.size()):
		var b := Button.new()
		b.text = tool_names[i]
		b.toggle_mode = true
		b.button_group = tool_group
		b.button_pressed = i == 0
		b.pressed.connect(_set_tool.bind(i))
		top.add_child(b)
		_tool_btns.append(b)

	var undo_btn := Button.new(); undo_btn.text = "Undo"
	var sc := Shortcut.new()
	var ev := InputEventKey.new()
	ev.keycode = KEY_Z
	ev.ctrl_pressed = true
	sc.events = [ev]
	undo_btn.shortcut = sc
	undo_btn.pressed.connect(_undo)
	top.add_child(undo_btn)

	top.add_child(VSeparator.new())
	top.add_child(_lbl("Zoom"))
	_zoom_pick = OptionButton.new()
	for z in [4, 6, 8, 12, 16]:
		_zoom_pick.add_item("%dx" % z)
	_zoom_pick.selected = 2
	_zoom_pick.item_selected.connect(_on_zoom_selected)
	top.add_child(_zoom_pick)

	var reg_chk := CheckBox.new()
	reg_chk.text = "Regions"
	reg_chk.button_pressed = true
	reg_chk.toggled.connect(func(v: bool): _show_regions = v; _canvas.queue_redraw())
	top.add_child(reg_chk)

	_size_lbl = Label.new()
	top.add_child(_size_lbl)

	# ── split: canvas | 3D preview ──
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.split_offset = 900
	vb.add_child(split)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(scroll)
	_canvas = PixelCanvas.new()
	_canvas.ed = self
	_canvas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	scroll.add_child(_canvas)

	var right := Control.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.custom_minimum_size = Vector2(360, 0)
	split.add_child(right)
	var cont := SubViewportContainer.new()
	cont.stretch = true
	cont.set_anchors_preset(Control.PRESET_FULL_RECT)
	cont.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.add_child(cont)
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
	_cam = Camera3D.new()
	vp.add_child(_cam)
	_cam.current = true
	_proot = Node3D.new()
	vp.add_child(_proot)
	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.gui_input.connect(_on_preview_input)
	right.add_child(overlay)

	_status = Label.new()
	_status.text = "  LMB: paint · RMB: eyedrop · live preview rebuilds as you draw"
	vb.add_child(_status)

	# dialogs
	_save_dialog = FileDialog.new()
	_save_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_save_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_save_dialog.add_filter("*.png ; PNG texture")
	_save_dialog.file_selected.connect(_on_save_file)
	add_child(_save_dialog)
	_load_dialog = FileDialog.new()
	_load_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_load_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_load_dialog.add_filter("*.png ; PNG texture")
	_load_dialog.file_selected.connect(_on_load_file)
	add_child(_load_dialog)
	var tex_dir := ProjectSettings.globalize_path("res://textures")
	if DirAccess.dir_exists_absolute(tex_dir):
		_save_dialog.current_dir = tex_dir
		_load_dialog.current_dir = tex_dir

	_preview_timer = Timer.new()
	_preview_timer.one_shot = true
	_preview_timer.wait_time = 0.30
	_preview_timer.timeout.connect(_rebuild_preview)
	add_child(_preview_timer)

func _lbl(t: String) -> Label:
	var l := Label.new(); l.text = t
	return l

# ─── canvas state ────────────────────────────────────────────────────────────
func _format_entry(layout: String) -> Array:
	for f in formats():
		if f[0] == layout:
			return f
	return formats()[0]

func _new_canvas(layout: String) -> void:
	_layout = layout
	var f := _format_entry(layout)
	_img = Image.create_empty(f[2], f[3], false, Image.FORMAT_RGBA8)
	_img.fill(Color(0.5, 0.5, 0.55, 1.0))
	_tex = ImageTexture.create_from_image(_img)
	_regions = regions_for(layout)
	_undo_stack.clear()
	for i in range(formats().size()):
		if formats()[i][0] == layout:
			_shape_pick.selected = i
	_size_lbl.text = "  %dx%d" % [f[2], f[3]]
	if _canvas:
		_canvas.refresh()
	_rebuild_preview()

# Derive the canvas from the current model so the editor always reflects what's
# on screen. `hint` is the model's stored block_shape (may be empty); if it's a
# layout we can rebuild, the atlas is reconstructed from the cells, otherwise we
# guess a cube layout from geometry.
func load_from_model(cells: Array, gx: int, gy: int, gz: int, hint: String) -> void:
	if cells.is_empty():
		return
	_model_cells = cells
	_model_gx = gx; _model_gy = gy; _model_gz = gz
	var layout := hint
	var atlas: Image = BlockImporter.reconstruct_atlas(layout, cells, gx, gy, gz) if layout != "" else null
	if atlas == null:
		layout = BlockImporter.guess_layout(cells, gx, gy, gz)
		atlas = BlockImporter.reconstruct_atlas(layout, cells, gx, gy, gz) if layout != "" else null
	if atlas == null:
		_status.text = "  couldn't derive an atlas from this model — pick a shape to try"
		return
	_apply_atlas(layout, atlas)
	_status.text = "  editing the current block's texture (%s)%s" % [layout, _divergence_note(layout, atlas)]

# Warn when the block's voxels carry per-face edits the shared-texel atlas can't
# hold (e.g. a chamfer's top painted differently from its bottom).
func _divergence_note(layout: String, atlas: Image) -> String:
	var n := BlockImporter.atlas_divergence(layout, _model_cells, atlas, _model_gx, _model_gy, _model_gz)
	if n > 0:
		return "  ·  ⚠ %d face(s) can't be shown in this atlas (top/bottom or shared faces differ)" % n
	return ""

# Set the canvas to `img` at `layout` (regions, size, preview all follow).
func _apply_atlas(layout: String, img: Image) -> void:
	_new_canvas(layout)
	_img = img
	_tex = ImageTexture.create_from_image(_img)
	_canvas.refresh()
	_rebuild_preview()

func _on_shape_selected(i: int) -> void:
	var f: Array = formats()[i]
	# Re-derive the atlas from the bound model under the newly chosen shape,
	# rather than blanking — this is how you correct a wrong initial guess.
	if not _model_cells.is_empty():
		var atlas := BlockImporter.reconstruct_atlas(f[0], _model_cells, _model_gx, _model_gy, _model_gz)
		if atlas != null:
			_apply_atlas(f[0], atlas)
			layout_chosen.emit(f[0])
			_status.text = "  re-read the model as %s%s" % [f[1], _divergence_note(f[0], atlas)]
			return
	_new_canvas(f[0])
	_status.text = "  new %s canvas (%dx%d)" % [f[1], f[2], f[3]]

func _on_zoom_selected(i: int) -> void:
	_zoom = [4, 6, 8, 12, 16][i]
	_canvas.refresh()

func _set_tool(t: int) -> void:
	_tool = t

func _undo() -> void:
	if _undo_stack.is_empty():
		return
	_img = _undo_stack.pop_back()
	_tex.update(_img)
	_canvas.queue_redraw()
	_preview_timer.start()

func _push_undo() -> void:
	_undo_stack.append(_img.duplicate())
	while _undo_stack.size() > 24:
		_undo_stack.pop_front()

# ─── painting ────────────────────────────────────────────────────────────────
func region_at(p: Vector2i) -> Dictionary:
	for reg in _regions:
		var rect: Rect2i = reg["rect"]
		if rect.has_point(p):
			return reg
	return {}

func _apply_tool(p: Vector2i) -> void:
	match _tool:
		TOOL_PENCIL:
			_img.set_pixelv(p, _color)
		TOOL_ERASE:
			_img.set_pixelv(p, Color(0, 0, 0, 0))
		TOOL_FILL:
			_flood_fill(p)
		TOOL_EYEDROP:
			_eyedrop(p)
			return
	_tex.update(_img)
	_canvas.queue_redraw()
	_preview_timer.start()

func _eyedrop(p: Vector2i) -> void:
	_color = _img.get_pixelv(p)
	_color.a = 1.0
	_color_btn.color = _color

# Flood fill bounded by the atlas region under the click (whole image if none).
func _flood_fill(p: Vector2i) -> void:
	var reg := region_at(p)
	var bounds: Rect2i = reg["rect"] if not reg.is_empty() else Rect2i(0, 0, _img.get_width(), _img.get_height())
	var src := _img.get_pixelv(p).to_rgba32()
	var dst := _color.to_rgba32()
	if src == dst:
		return
	var stack: Array = [p]
	while not stack.is_empty():
		var q: Vector2i = stack.pop_back()
		if not bounds.has_point(q):
			continue
		if _img.get_pixelv(q).to_rgba32() != src:
			continue
		_img.set_pixelv(q, _color)
		stack.append(Vector2i(q.x + 1, q.y))
		stack.append(Vector2i(q.x - 1, q.y))
		stack.append(Vector2i(q.x, q.y + 1))
		stack.append(Vector2i(q.x, q.y - 1))

func _stroke_to(p: Vector2i) -> void:
	if _last_px.x < 0:
		_apply_tool(p)
	else:
		var n := maxi(1, maxi(absi(p.x - _last_px.x), absi(p.y - _last_px.y)))
		for i in range(n + 1):
			var t := float(i) / float(n)
			var q := Vector2i(roundi(lerpf(_last_px.x, p.x, t)), roundi(lerpf(_last_px.y, p.y, t)))
			if _tool == TOOL_PENCIL:
				_img.set_pixelv(q, _color)
			elif _tool == TOOL_ERASE:
				_img.set_pixelv(q, Color(0, 0, 0, 0))
		_tex.update(_img)
		_canvas.queue_redraw()
		_preview_timer.start()
	_last_px = p

func canvas_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var p := _canvas.pixel_at(event.position)
		if p.x < 0:
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				if _tool in [TOOL_PENCIL, TOOL_ERASE, TOOL_FILL]:
					_push_undo()
				_painting = true
				_last_px = Vector2i(-1, -1)
				_apply_tool(p)
				_last_px = p
			else:
				_painting = false
				_last_px = Vector2i(-1, -1)
				_rebuild_preview()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_eyedrop(p)
	elif event is InputEventMouseMotion:
		var p := _canvas.pixel_at(event.position)
		if p.x >= 0:
			var reg := region_at(p)
			var rn: String = reg["name"] if not reg.is_empty() else "-"
			_status.text = "  %d, %d · %s" % [p.x, p.y, rn]
			if _painting and _tool in [TOOL_PENCIL, TOOL_ERASE]:
				_stroke_to(p)

# ─── 3D preview ──────────────────────────────────────────────────────────────
func _rebuild_preview() -> void:
	for c in _proot.get_children():
		c.queue_free()
	var cells := BlockImporter.build_cells(_layout, _img, GX, GX, GX, BlockImporter.default_opt(_layout))
	var mesh := BlockMeshBuilder.build_mesh(cells, GX, GX, GX, CELL)
	if mesh and mesh.get_surface_count() > 0:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		for si in range(mesh.get_surface_count()):
			mi.set_surface_override_material(si, _pmat)
		_proot.add_child(mi)
	_update_camera()

func _update_camera() -> void:
	var offset := Vector3(sin(_yaw) * cos(_pitch), sin(_pitch), cos(_yaw) * cos(_pitch)) * _dist
	_cam.position = _pivot + offset
	_cam.look_at(_pivot, Vector3.UP)

func _on_preview_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_RIGHT:
				_rmb = event.pressed
			MOUSE_BUTTON_MIDDLE:
				_pan = event.pressed
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed:
					_dist = maxf(4.0, _dist * 0.9)
					_update_camera()
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					_dist *= 1.1
					_update_camera()
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

# ─── save / load ─────────────────────────────────────────────────────────────
func _sanitize(s: String) -> String:
	var out := s.strip_edges().to_lower().replace(" ", "-").replace("_", "-")
	var keep := ""
	for ch in out:
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") or ch == "-" or ch == ".":
			keep += ch
	return keep if not keep.is_empty() else "material"

func _default_filename() -> String:
	var f := _format_entry(_layout)
	return "%s_%s_%dx%d.png" % [_sanitize(_name_edit.text), f[1], f[2], f[3]]

func _on_save_pressed() -> void:
	_save_dialog.current_file = _default_filename()
	_save_dialog.popup_centered(Vector2i(760, 520))

func _on_save_file(path: String) -> void:
	var err := _img.save_png(path)
	_status.text = ("  saved " + path.get_file()) if err == OK else ("  save failed (err %d)" % err)

func _on_load_file(path: String) -> void:
	var img := Image.new()
	if img.load(path) != OK:
		_status.text = "  could not load " + path.get_file()
		return
	var layout := CellTypes.validate_block_texture(img.get_width(), img.get_height(), GX, GX)
	if layout == "":
		_status.text = "  %s is %dx%d — not a legal atlas size" % [path.get_file(), img.get_width(), img.get_height()]
		return
	img.convert(Image.FORMAT_RGBA8)
	_new_canvas(layout)
	_img = img
	_tex = ImageTexture.create_from_image(_img)
	_canvas.refresh()
	# material field from the filename: strip _WxH, then the trailing _shape
	var base := path.get_file().get_basename()
	var re := RegEx.new()
	re.compile("_\\d+x\\d+$")
	var m := re.search(base)
	if m:
		base = base.substr(0, m.get_start())
	var us := base.rfind("_")
	if us > 0:
		base = base.substr(0, us)
	_name_edit.text = base
	_rebuild_preview()
	_status.text = "  loaded %s as %s" % [path.get_file(), layout]

# ─── pixel canvas (inner) ────────────────────────────────────────────────────
class PixelCanvas extends Control:
	var ed: TextureEditor

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		gui_input.connect(func(e: InputEvent): ed.canvas_input(e))

	func refresh() -> void:
		custom_minimum_size = Vector2(ed._img.get_width() * ed._zoom, ed._img.get_height() * ed._zoom)
		queue_redraw()

	func pixel_at(pos: Vector2) -> Vector2i:
		var p := Vector2i(int(pos.x / ed._zoom), int(pos.y / ed._zoom))
		if p.x < 0 or p.y < 0 or p.x >= ed._img.get_width() or p.y >= ed._img.get_height():
			return Vector2i(-1, -1)
		return p

	func _draw() -> void:
		if ed._img == null:
			return
		var z: int = ed._zoom
		var w: int = ed._img.get_width()
		var h: int = ed._img.get_height()
		draw_rect(Rect2(0, 0, w * z, h * z), Color(0.13, 0.13, 0.16))
		draw_texture_rect(ed._tex, Rect2(0, 0, w * z, h * z), false)
		# texel grid
		if z >= 6:
			for x in range(w + 1):
				var a := 0.25 if x % 8 == 0 else 0.09
				draw_line(Vector2(x * z, 0), Vector2(x * z, h * z), Color(1, 1, 1, a))
			for y in range(h + 1):
				var a2 := 0.25 if y % 8 == 0 else 0.09
				draw_line(Vector2(0, y * z), Vector2(w * z, y * z), Color(1, 1, 1, a2))
		# region overlays: orange borders (colorblind-safe), dimmed if unused
		if ed._show_regions:
			var font := get_theme_default_font()
			for reg in ed._regions:
				var rect: Rect2i = reg["rect"]
				var nm: String = reg["name"]
				var rr := Rect2(rect.position * z, rect.size * z)
				var col := Color(1.0, 0.62, 0.0, 0.9) if nm != "unused" else Color(0.5, 0.5, 0.5, 0.5)
				draw_rect(rr, col, false, 2.0)
				if rect.size.x * z >= 34 and rect.size.y * z >= 14:
					var tp := rr.position + Vector2(3, 12)
					draw_string(font, tp + Vector2(1, 1), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0, 0, 0, 0.9))
					draw_string(font, tp, nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.95))
