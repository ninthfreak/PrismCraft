class_name TileView
extends Window

# View-only tiling preview: renders the current block repeated in a grid so you
# can see how it reads when placed edge-to-edge. The block can be rotated in 90°
# steps (all tiles share the rotation) and tiled independently along X / Y / Z.
# A single MultiMesh instances one block mesh, so large tile counts stay cheap.

const CELL := 1.0

# Emitted by the "Refresh from Editor" button; the editor reconnects it to re-push
# the current working model.
signal refresh_requested

var _cam: Camera3D
var _root: Node3D
var _mmi: MultiMeshInstance3D
var _mat: ShaderMaterial
var _info: Label

# source model
var _cells: Array = []
var _gx := 32
var _gy := 32
var _gz := 32

# tiling + rotation state
var _nx := 3
var _ny := 1
var _nz := 3
var _rot := Basis()          # accumulated 90° block rotation, applied to every tile
var _sx: SpinBox
var _sy: SpinBox
var _sz: SpinBox

# orbit camera
var _yaw := -PI / 4.0
var _pitch := PI / 6.0
var _pivot := Vector3.ZERO
var _dist := 60.0
var _rmb := false
var _pan := false

func _init() -> void:
	title = "Tiling Preview (view only)"
	size = Vector2i(1200, 820)
	min_size = Vector2i(760, 500)
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

	# top bar: tile counts + rotation + refresh
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	vb.add_child(top)

	top.add_child(_label("Tiles  X"))
	_sx = _spin(1, 12, _nx, func(v): _nx = int(v); _rebuild())
	top.add_child(_sx)
	top.add_child(_label("Y"))
	_sy = _spin(1, 12, _ny, func(v): _ny = int(v); _rebuild())
	top.add_child(_sy)
	top.add_child(_label("Z"))
	_sz = _spin(1, 12, _nz, func(v): _nz = int(v); _rebuild())
	top.add_child(_sz)

	top.add_child(VSeparator.new())
	top.add_child(_label("Rotate"))
	top.add_child(_rot_btn("X", Vector3(1, 0, 0)))
	top.add_child(_rot_btn("Y", Vector3(0, 1, 0)))
	top.add_child(_rot_btn("Z", Vector3(0, 0, 1)))
	var rr := Button.new(); rr.text = "Reset Rot"
	rr.pressed.connect(func(): _rot = Basis(); _rebuild())
	top.add_child(rr)

	top.add_child(VSeparator.new())
	var refresh := Button.new(); refresh.text = "Refresh from Editor"
	refresh.pressed.connect(_emit_refresh)
	top.add_child(refresh)
	var reset := Button.new(); reset.text = "Reset View"
	reset.pressed.connect(_reset_view)
	top.add_child(reset)

	# 3D content + input overlay
	var content := Control.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(content)

	var cont := SubViewportContainer.new()
	cont.stretch = true
	cont.set_anchors_preset(Control.PRESET_FULL_RECT)
	cont.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(cont)
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
	_root = Node3D.new()
	vp.add_child(_root)

	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.gui_input.connect(_on_view_input)
	content.add_child(overlay)

	_info = Label.new()
	_info.text = "  Right-drag: rotate view  ·  Wheel: zoom  ·  Middle-drag: pan  ·  view only, no editing"
	vb.add_child(_info)

func _label(t: String) -> Label:
	var l := Label.new(); l.text = t
	return l

func _spin(lo: int, hi: int, val: int, cb: Callable) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = lo; s.max_value = hi; s.step = 1; s.value = val
	s.value_changed.connect(cb)
	return s

func _rot_btn(txt: String, axis: Vector3) -> Button:
	var b := Button.new(); b.text = txt
	b.tooltip_text = "Rotate the block 90° about " + txt
	b.pressed.connect(_rotate_block.bind(axis))
	return b

func _rotate_block(axis: Vector3) -> void:
	_rot = (Basis(axis, PI / 2.0) * _rot).orthonormalized()
	_rebuild()

func _emit_refresh() -> void:
	refresh_requested.emit()

func set_model(cells: Array, gx: int, gy: int, gz: int) -> void:
	_cells = cells
	_gx = gx; _gy = gy; _gz = gz
	_rebuild()

func _rebuild() -> void:
	for c in _root.get_children():
		c.queue_free()
	_mmi = null
	if _cells.is_empty():
		_update_info(0)
		return
	var mesh := BlockMeshBuilder.build_mesh(_cells, _gx, _gy, _gz, CELL)
	if mesh == null or mesh.get_surface_count() == 0:
		_update_info(0)
		return

	var count := _nx * _ny * _nz
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = count

	# Rotate each tile about the block's own center, then translate into the grid.
	var half := Vector3(_gx, _gy, _gz) * CELL * 0.5
	var about_center := Transform3D(_rot, half - _rot * half)
	var i := 0
	for iz in range(_nz):
		for iy in range(_ny):
			for ix in range(_nx):
				var origin := Vector3(ix * _gx, iy * _gy, iz * _gz) * CELL
				mm.set_instance_transform(i, Transform3D(Basis(), origin) * about_center)
				i += 1

	_mmi = MultiMeshInstance3D.new()
	_mmi.multimesh = mm
	_mmi.material_override = _mat
	_root.add_child(_mmi)

	_pivot = Vector3(_nx * _gx, _ny * _gy, _nz * _gz) * CELL * 0.5
	_dist = maxf(_nx * _gx, maxf(_ny * _gy, _nz * _gz)) * CELL * 1.5
	_update_camera()
	_update_info(count)

func _update_info(count: int) -> void:
	if _info == null:
		return
	if count == 0:
		_info.text = "  (empty model — draw something, then Refresh from Editor)"
	else:
		_info.text = "  %d×%d×%d = %d tiles   ·   Right-drag: rotate view · Wheel: zoom · Middle-drag: pan · view only" % [_nx, _ny, _nz, count]

func _reset_view() -> void:
	_yaw = -PI / 4.0
	_pitch = PI / 6.0
	_update_camera()

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
					_dist = maxf(0.5, _dist * 0.9)
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
