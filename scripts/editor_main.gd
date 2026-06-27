extends Node3D

enum EditMode { BLOCK, CHARACTER }
enum ToolType { PENCIL, BOX, ERASER, BOX_ERASE }

const CELL_RES := 32
const CELL_SIZE := 1.0 / CELL_RES
const PANEL_WIDTH := 180

var edit_mode: int = EditMode.BLOCK
var grid_x := 32
var grid_y := 32
var grid_z := 32

var cells: Array = []
var current_tool: int = ToolType.PENCIL
var current_type: int = CellTypes.Type.SOLID
var current_orientation: int = 0
var current_color: int = 0
var current_file_path := ""
var floor_y: int = 0

var box_start := Vector3i(-1, -1, -1)
var box_active := false

var place_cell := Vector3i(-1, -1, -1)
var target_cell := Vector3i(-1, -1, -1)

var mesh_instance: MeshInstance3D
var collision_body: StaticBody3D
var collision_shape: CollisionShape3D
var grid_mesh_instance: MeshInstance3D
var cursor_mesh_instance: MeshInstance3D
var box_preview_instance: MeshInstance3D

var ui_layer: CanvasLayer
var panel: PanelContainer
var coord_label: Label
var file_label: Label
var orient_container: HBoxContainer
var orient_label: Label
var floor_slider: HSlider
var floor_value_label: Label

var mode_group: ButtonGroup
var tool_group: ButtonGroup
var type_group: ButtonGroup
var color_group: ButtonGroup

var save_dialog: FileDialog
var open_dialog: FileDialog

@onready var camera: Camera3D = $Camera3D

# ─── Lifecycle ───

func _ready() -> void:
	_init_cells()
	_setup_scene()
	_setup_ui()
	_rebuild_mesh()
	_rebuild_grid()
	_center_camera()
	_generate_presets()

func _generate_presets() -> void:
	DirAccess.make_dir_recursive_absolute("res://definitions")
	ResourceSaver.save(VoxelDefinition.create_male(), "res://definitions/male.tres")
	ResourceSaver.save(VoxelDefinition.create_female(), "res://definitions/female.tres")

func _center_camera() -> void:
	camera.pivot = Vector3(grid_x, grid_y, grid_z) * CELL_SIZE * 0.5

func _init_cells() -> void:
	cells.resize(grid_x)
	for x in range(grid_x):
		cells[x] = []
		cells[x].resize(grid_y)
		for y in range(grid_y):
			cells[x][y] = []
			cells[x][y].resize(grid_z)
			for z in range(grid_z):
				cells[x][y][z] = [CellTypes.Type.EMPTY, 0, 0]

# ─── Scene Setup ───

func _setup_scene() -> void:
	mesh_instance = MeshInstance3D.new()
	add_child(mesh_instance)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mesh_instance.material_override = mat

	collision_body = StaticBody3D.new()
	add_child(collision_body)
	collision_shape = CollisionShape3D.new()
	collision_body.add_child(collision_shape)

	grid_mesh_instance = MeshInstance3D.new()
	add_child(grid_mesh_instance)

	cursor_mesh_instance = MeshInstance3D.new()
	add_child(cursor_mesh_instance)
	cursor_mesh_instance.visible = false

	box_preview_instance = MeshInstance3D.new()
	add_child(box_preview_instance)
	box_preview_instance.visible = false
	var box_mat := StandardMaterial3D.new()
	box_mat.albedo_color = Color(1, 1, 0, 0.6)
	box_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	box_mat.no_depth_test = true
	box_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	box_preview_instance.material_override = box_mat

# ─── UI Panel ───

func _setup_ui() -> void:
	ui_layer = CanvasLayer.new()
	add_child(ui_layer)

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.12, 0.12, 0.15, 0.92)
	panel_style.content_margin_left = 8
	panel_style.content_margin_right = 8
	panel_style.content_margin_top = 8
	panel_style.content_margin_bottom = 8

	panel = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", panel_style)
	panel.position = Vector2.ZERO
	panel.custom_minimum_size = Vector2(PANEL_WIDTH, 720)
	ui_layer.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)

	# Title
	var title := Label.new()
	title.text = "PrismCraft Editor"
	title.add_theme_font_size_override("font_size", 15)
	vbox.add_child(title)
	vbox.add_child(HSeparator.new())

	# Mode
	_add_section_label(vbox, "Mode")
	mode_group = ButtonGroup.new()
	var mode_row := _add_button_row(vbox, ["Block", "Character"], mode_group)
	mode_row[0].button_pressed = true
	mode_group.pressed.connect(_on_mode_pressed)

	vbox.add_child(HSeparator.new())

	# Tool
	_add_section_label(vbox, "Tool")
	tool_group = ButtonGroup.new()
	var tool_row1 := _add_button_row(vbox, ["Pencil", "Box Fill"], tool_group)
	var tool_row2 := _add_button_row(vbox, ["Eraser", "Box Erase"], tool_group)
	tool_row1[0].button_pressed = true
	tool_group.pressed.connect(_on_tool_pressed)

	vbox.add_child(HSeparator.new())

	# Cell Type
	_add_section_label(vbox, "Cell Type")
	type_group = ButtonGroup.new()
	var type_row := _add_button_row(vbox, ["Solid", "Prism"], type_group)
	type_row[0].button_pressed = true
	type_group.pressed.connect(_on_type_pressed)

	orient_container = HBoxContainer.new()
	orient_container.visible = false
	vbox.add_child(orient_container)
	var orient_prev := Button.new()
	orient_prev.text = "<"
	orient_prev.custom_minimum_size = Vector2(30, 0)
	orient_prev.pressed.connect(func(): _cycle_orientation(-1))
	orient_container.add_child(orient_prev)
	orient_label = Label.new()
	orient_label.text = CellTypes.get_orientation_name(0)
	orient_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	orient_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	orient_container.add_child(orient_label)
	var orient_next := Button.new()
	orient_next.text = ">"
	orient_next.custom_minimum_size = Vector2(30, 0)
	orient_next.pressed.connect(func(): _cycle_orientation(1))
	orient_container.add_child(orient_next)

	vbox.add_child(HSeparator.new())

	# Color
	_add_section_label(vbox, "Color")
	color_group = ButtonGroup.new()
	var color_grid := GridContainer.new()
	color_grid.columns = 4
	vbox.add_child(color_grid)
	for i in range(CellTypes.PALETTE.size()):
		var btn := Button.new()
		btn.toggle_mode = true
		btn.button_group = color_group
		btn.custom_minimum_size = Vector2(36, 28)
		btn.tooltip_text = CellTypes.PALETTE_NAMES[i]
		var ns := StyleBoxFlat.new()
		ns.bg_color = CellTypes.PALETTE[i]
		ns.border_color = Color(0.4, 0.4, 0.4)
		ns.set_border_width_all(1)
		btn.add_theme_stylebox_override("normal", ns)
		btn.add_theme_stylebox_override("hover", ns)
		var ps := StyleBoxFlat.new()
		ps.bg_color = CellTypes.PALETTE[i]
		ps.border_color = Color.WHITE
		ps.set_border_width_all(3)
		btn.add_theme_stylebox_override("pressed", ps)
		if i == 0:
			btn.button_pressed = true
		color_grid.add_child(btn)
	color_group.pressed.connect(_on_color_pressed)

	vbox.add_child(HSeparator.new())

	# Floor
	_add_section_label(vbox, "Floor Layer")
	var floor_row := HBoxContainer.new()
	vbox.add_child(floor_row)
	var floor_down := Button.new()
	floor_down.text = "-"
	floor_down.custom_minimum_size = Vector2(28, 0)
	floor_down.pressed.connect(func(): _set_floor(floor_y - 1))
	floor_row.add_child(floor_down)
	floor_slider = HSlider.new()
	floor_slider.min_value = 0
	floor_slider.max_value = grid_y - 1
	floor_slider.step = 1
	floor_slider.value = 0
	floor_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	floor_slider.value_changed.connect(func(v: float): _set_floor(int(v)))
	floor_row.add_child(floor_slider)
	var floor_up := Button.new()
	floor_up.text = "+"
	floor_up.custom_minimum_size = Vector2(28, 0)
	floor_up.pressed.connect(func(): _set_floor(floor_y + 1))
	floor_row.add_child(floor_up)
	floor_value_label = Label.new()
	floor_value_label.text = "Y = 0"
	vbox.add_child(floor_value_label)

	vbox.add_child(HSeparator.new())

	# File info
	file_label = Label.new()
	file_label.text = "File: (unsaved)"
	file_label.add_theme_font_size_override("font_size", 11)
	vbox.add_child(file_label)

	coord_label = Label.new()
	coord_label.add_theme_font_size_override("font_size", 11)
	vbox.add_child(coord_label)

	# Help at bottom of screen
	var help := Label.new()
	help.position = Vector2(PANEL_WIDTH + 10, 690)
	help.add_theme_font_size_override("font_size", 11)
	help.text = "Ctrl+S: Save | Ctrl+O: Open | Ctrl+N: New | Up/Down: Floor | Esc: Cancel box"
	ui_layer.add_child(help)

	# File dialogs
	save_dialog = FileDialog.new()
	save_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	save_dialog.access = FileDialog.ACCESS_RESOURCES
	save_dialog.add_filter("*.tres ; Voxel Definition")
	save_dialog.title = "Save Definition"
	save_dialog.size = Vector2i(700, 500)
	save_dialog.file_selected.connect(_on_save_file_selected)
	add_child(save_dialog)

	open_dialog = FileDialog.new()
	open_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	open_dialog.access = FileDialog.ACCESS_RESOURCES
	open_dialog.add_filter("*.tres ; Voxel Definition")
	open_dialog.title = "Open Definition"
	open_dialog.size = Vector2i(700, 500)
	open_dialog.file_selected.connect(_on_open_file_selected)
	add_child(open_dialog)

func _add_section_label(parent: VBoxContainer, text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
	parent.add_child(lbl)

func _add_button_row(parent: VBoxContainer, names: Array, group: ButtonGroup) -> Array[Button]:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	parent.add_child(row)
	var buttons: Array[Button] = []
	for n in names:
		var btn := Button.new()
		btn.text = n
		btn.toggle_mode = true
		btn.button_group = group
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(0, 28)
		row.add_child(btn)
		buttons.append(btn)
	return buttons

# ─── Panel Callbacks ───

func _on_mode_pressed(btn: BaseButton) -> void:
	if btn.text == "Block":
		_set_edit_mode(EditMode.BLOCK)
	else:
		_set_edit_mode(EditMode.CHARACTER)

func _on_tool_pressed(btn: BaseButton) -> void:
	match btn.text:
		"Pencil": current_tool = ToolType.PENCIL
		"Box Fill": current_tool = ToolType.BOX
		"Eraser": current_tool = ToolType.ERASER
		"Box Erase": current_tool = ToolType.BOX_ERASE
	_cancel_box()

func _on_type_pressed(btn: BaseButton) -> void:
	if btn.text == "Solid":
		current_type = CellTypes.Type.SOLID
		orient_container.visible = false
	else:
		current_type = CellTypes.Type.PRISM
		orient_container.visible = true
	_update_raycast()

func _on_color_pressed(btn: BaseButton) -> void:
	var buttons := color_group.get_buttons()
	for i in range(buttons.size()):
		if buttons[i] == btn:
			current_color = i
			break

func _cycle_orientation(delta: int) -> void:
	current_orientation = (current_orientation + delta) % 12
	if current_orientation < 0:
		current_orientation += 12
	orient_label.text = CellTypes.get_orientation_name(current_orientation)
	_update_raycast()

func _set_floor(y: int) -> void:
	floor_y = clampi(y, 0, grid_y - 1)
	floor_slider.set_value_no_signal(floor_y)
	floor_value_label.text = "Y = %d" % floor_y
	_rebuild_grid()

func _set_edit_mode(mode: int) -> void:
	if mode == edit_mode:
		return
	edit_mode = mode
	if edit_mode == EditMode.BLOCK:
		grid_x = 32; grid_y = 32; grid_z = 32
	else:
		grid_x = 32; grid_y = 64; grid_z = 32
	current_file_path = ""
	place_cell = Vector3i(-1, -1, -1)
	target_cell = Vector3i(-1, -1, -1)
	cursor_mesh_instance.visible = false
	_cancel_box()
	floor_y = 0
	floor_slider.max_value = grid_y - 1
	floor_slider.set_value_no_signal(0)
	floor_value_label.text = "Y = 0"
	_init_cells()
	_rebuild_mesh()
	_rebuild_grid()
	_center_camera()
	_update_file_label()

# ─── Input ───

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.ctrl_pressed:
			match event.keycode:
				KEY_S: _save(); get_viewport().set_input_as_handled(); return
				KEY_O: _open(); get_viewport().set_input_as_handled(); return
				KEY_N: _new(); get_viewport().set_input_as_handled(); return

		match event.keycode:
			KEY_TAB:
				_toggle_type()
				get_viewport().set_input_as_handled()
			KEY_Q: _cycle_orientation(-1)
			KEY_E: _cycle_orientation(1)
			KEY_UP: _set_floor(floor_y + 1)
			KEY_DOWN: _set_floor(floor_y - 1)
			KEY_ESCAPE: _cancel_box()
			KEY_1: _select_color(0)
			KEY_2: _select_color(1)
			KEY_3: _select_color(2)
			KEY_4: _select_color(3)
			KEY_5: _select_color(4)
			KEY_6: _select_color(5)
			KEY_7: _select_color(6)
			KEY_8: _select_color(7)

	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_on_left_click()
		if not event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			if camera and not camera.was_orbit_drag():
				_on_right_click()

	if event is InputEventMouseMotion:
		_update_raycast()

func _toggle_type() -> void:
	if current_type == CellTypes.Type.SOLID:
		current_type = CellTypes.Type.PRISM
		orient_container.visible = true
	else:
		current_type = CellTypes.Type.SOLID
		orient_container.visible = false
	var buttons := type_group.get_buttons()
	buttons[0].button_pressed = current_type == CellTypes.Type.SOLID
	buttons[1].button_pressed = current_type == CellTypes.Type.PRISM
	_update_raycast()

func _select_color(idx: int) -> void:
	current_color = idx
	var buttons := color_group.get_buttons()
	if idx < buttons.size():
		buttons[idx].button_pressed = true

# ─── Raycasting ───

func _update_raycast() -> void:
	if not camera:
		return

	var mouse_pos := get_viewport().get_mouse_position()
	if mouse_pos.x < PANEL_WIDTH:
		return

	var from := camera.project_ray_origin(mouse_pos)
	var dir := camera.project_ray_normal(mouse_pos)

	place_cell = Vector3i(-1, -1, -1)
	target_cell = Vector3i(-1, -1, -1)

	var geo_dist := INF
	var floor_dist := INF

	# Geometry raycast
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, from + dir * 100.0)
	var result := space.intersect_ray(query)

	if result:
		var hit_pos: Vector3 = result["position"]
		var hit_normal: Vector3 = result["normal"]
		geo_dist = from.distance_to(hit_pos)
		target_cell = _world_to_cell(hit_pos - hit_normal * 0.01)
		var adj := _world_to_cell(hit_pos + hit_normal * 0.01)
		if _in_bounds(adj) and cells[adj.x][adj.y][adj.z][0] == CellTypes.Type.EMPTY:
			place_cell = adj

	# Floor plane raycast
	var floor_world_y := floor_y * CELL_SIZE
	if abs(dir.y) > 0.0001:
		var t := (floor_world_y - from.y) / dir.y
		if t > 0:
			floor_dist = t * dir.length()
			var hit := from + dir * t
			var fc := _world_to_cell(hit)
			fc.y = floor_y
			if _in_bounds(fc):
				if floor_dist < geo_dist and cells[fc.x][fc.y][fc.z][0] == CellTypes.Type.EMPTY:
					place_cell = fc
				elif geo_dist == INF:
					place_cell = fc

	# Update cursor display
	var cursor_pos: Vector3i
	if current_tool == ToolType.ERASER or current_tool == ToolType.BOX_ERASE:
		cursor_pos = target_cell
	else:
		cursor_pos = place_cell

	if _in_bounds(cursor_pos):
		_draw_cursor(cursor_pos)
		cursor_mesh_instance.visible = true
		coord_label.text = "Cell: (%d, %d, %d)" % [cursor_pos.x, cursor_pos.y, cursor_pos.z]
	else:
		cursor_mesh_instance.visible = false
		coord_label.text = ""

	_update_box_preview()

func _world_to_cell(world_pos: Vector3) -> Vector3i:
	return Vector3i(
		int(floor(world_pos.x / CELL_SIZE)),
		int(floor(world_pos.y / CELL_SIZE)),
		int(floor(world_pos.z / CELL_SIZE))
	)

func _in_bounds(pos: Vector3i) -> bool:
	return pos.x >= 0 and pos.x < grid_x and pos.y >= 0 and pos.y < grid_y and pos.z >= 0 and pos.z < grid_z

# ─── Click Actions ───

func _on_left_click() -> void:
	match current_tool:
		ToolType.PENCIL:
			if _in_bounds(place_cell):
				cells[place_cell.x][place_cell.y][place_cell.z] = [current_type, current_orientation, current_color]
				_rebuild_mesh()
		ToolType.BOX:
			if not box_active:
				if _in_bounds(place_cell):
					box_start = place_cell
					box_active = true
			else:
				if _in_bounds(place_cell):
					_fill_region(box_start, place_cell, current_type, current_orientation, current_color)
				_cancel_box()
		ToolType.ERASER:
			if _in_bounds(target_cell) and cells[target_cell.x][target_cell.y][target_cell.z][0] != CellTypes.Type.EMPTY:
				cells[target_cell.x][target_cell.y][target_cell.z] = [CellTypes.Type.EMPTY, 0, 0]
				_rebuild_mesh()
		ToolType.BOX_ERASE:
			if not box_active:
				if _in_bounds(target_cell):
					box_start = target_cell
					box_active = true
			else:
				if _in_bounds(target_cell):
					_clear_region(box_start, target_cell)
				_cancel_box()

func _on_right_click() -> void:
	if box_active:
		_cancel_box()

func _cancel_box() -> void:
	box_active = false
	box_start = Vector3i(-1, -1, -1)
	box_preview_instance.visible = false

func _fill_region(a: Vector3i, b: Vector3i, cell_type: int, orientation: int, color_idx: int) -> void:
	var mn := Vector3i(mini(a.x, b.x), mini(a.y, b.y), mini(a.z, b.z))
	var mx := Vector3i(maxi(a.x, b.x), maxi(a.y, b.y), maxi(a.z, b.z))
	for x in range(maxi(0, mn.x), mini(grid_x, mx.x + 1)):
		for y in range(maxi(0, mn.y), mini(grid_y, mx.y + 1)):
			for z in range(maxi(0, mn.z), mini(grid_z, mx.z + 1)):
				cells[x][y][z] = [cell_type, orientation, color_idx]
	_rebuild_mesh()

func _clear_region(a: Vector3i, b: Vector3i) -> void:
	var mn := Vector3i(mini(a.x, b.x), mini(a.y, b.y), mini(a.z, b.z))
	var mx := Vector3i(maxi(a.x, b.x), maxi(a.y, b.y), maxi(a.z, b.z))
	for x in range(maxi(0, mn.x), mini(grid_x, mx.x + 1)):
		for y in range(maxi(0, mn.y), mini(grid_y, mx.y + 1)):
			for z in range(maxi(0, mn.z), mini(grid_z, mx.z + 1)):
				cells[x][y][z] = [CellTypes.Type.EMPTY, 0, 0]
	_rebuild_mesh()

# ─── Cursor Drawing ───

func _get_prism_vertices(origin: Vector3, s: float, orientation: int) -> Array:
	var axis: int = orientation / 4
	var corner: int = orientation % 4
	var tri_2d: Array[Vector2]
	match corner:
		0: tri_2d = [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1)]
		1: tri_2d = [Vector2(1, 0), Vector2(1, 1), Vector2(0, 0)]
		2: tri_2d = [Vector2(1, 1), Vector2(0, 1), Vector2(1, 0)]
		_: tri_2d = [Vector2(0, 1), Vector2(0, 0), Vector2(1, 1)]
	var p_near: Array[Vector3] = []
	var p_far: Array[Vector3] = []
	for uv in tri_2d:
		match axis:
			0:
				p_near.append(origin + Vector3(uv.x * s, 0, uv.y * s))
				p_far.append(origin + Vector3(uv.x * s, s, uv.y * s))
			1:
				p_near.append(origin + Vector3(0, uv.x * s, uv.y * s))
				p_far.append(origin + Vector3(s, uv.x * s, uv.y * s))
			_:
				p_near.append(origin + Vector3(uv.x * s, uv.y * s, 0))
				p_far.append(origin + Vector3(uv.x * s, uv.y * s, s))
	return [p_near, p_far]

func _draw_cursor(cell_pos: Vector3i) -> void:
	var margin := CELL_SIZE * 0.02
	var pos := Vector3(cell_pos) * CELL_SIZE - Vector3.ONE * margin
	var size := CELL_SIZE + margin * 2.0

	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)

	var is_erase := current_tool == ToolType.ERASER or current_tool == ToolType.BOX_ERASE
	if is_erase or current_type == CellTypes.Type.SOLID:
		var c: Array[Vector3] = [
			pos, pos + Vector3(size, 0, 0), pos + Vector3(size, 0, size), pos + Vector3(0, 0, size),
			pos + Vector3(0, size, 0), pos + Vector3(size, size, 0),
			pos + Vector3(size, size, size), pos + Vector3(0, size, size),
		]
		for e in [[0,1],[1,2],[2,3],[3,0],[4,5],[5,6],[6,7],[7,4],[0,4],[1,5],[2,6],[3,7]]:
			im.surface_add_vertex(c[e[0]])
			im.surface_add_vertex(c[e[1]])
	else:
		var verts := _get_prism_vertices(pos, size, current_orientation)
		var p_near: Array = verts[0]
		var p_far: Array = verts[1]
		for i in range(3):
			im.surface_add_vertex(p_near[i]); im.surface_add_vertex(p_near[(i + 1) % 3])
			im.surface_add_vertex(p_far[i]); im.surface_add_vertex(p_far[(i + 1) % 3])
			im.surface_add_vertex(p_near[i]); im.surface_add_vertex(p_far[i])

	im.surface_end()
	cursor_mesh_instance.mesh = im

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color.RED if is_erase else Color.WHITE
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	cursor_mesh_instance.material_override = mat

func _update_box_preview() -> void:
	if not box_active:
		box_preview_instance.visible = false
		return
	var end_cell: Vector3i
	if current_tool == ToolType.BOX:
		end_cell = place_cell
	else:
		end_cell = target_cell
	if not _in_bounds(end_cell):
		box_preview_instance.visible = false
		return

	var mn := Vector3(
		mini(box_start.x, end_cell.x),
		mini(box_start.y, end_cell.y),
		mini(box_start.z, end_cell.z)) * CELL_SIZE
	var mx := Vector3(
		maxi(box_start.x, end_cell.x) + 1,
		maxi(box_start.y, end_cell.y) + 1,
		maxi(box_start.z, end_cell.z) + 1) * CELL_SIZE

	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	var c: Array[Vector3] = [
		mn, Vector3(mx.x, mn.y, mn.z), Vector3(mx.x, mn.y, mx.z), Vector3(mn.x, mn.y, mx.z),
		Vector3(mn.x, mx.y, mn.z), Vector3(mx.x, mx.y, mn.z), mx, Vector3(mn.x, mx.y, mx.z),
	]
	for e in [[0,1],[1,2],[2,3],[3,0],[4,5],[5,6],[6,7],[7,4],[0,4],[1,5],[2,6],[3,7]]:
		im.surface_add_vertex(c[e[0]])
		im.surface_add_vertex(c[e[1]])
	im.surface_end()
	box_preview_instance.mesh = im
	box_preview_instance.visible = true

# ─── File Operations ───

func _save() -> void:
	if current_file_path.is_empty():
		save_dialog.current_dir = "res://definitions"
		save_dialog.popup_centered()
	else:
		_save_to_path(current_file_path)

func _open() -> void:
	open_dialog.current_dir = "res://definitions"
	open_dialog.popup_centered()

func _new() -> void:
	current_file_path = ""
	_cancel_box()
	place_cell = Vector3i(-1, -1, -1)
	target_cell = Vector3i(-1, -1, -1)
	cursor_mesh_instance.visible = false
	_init_cells()
	_rebuild_mesh()
	_update_file_label()

func _save_to_path(path: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var def := VoxelDefinition.new()
	def.set_from_cells(cells, grid_x, grid_y, grid_z, edit_mode)
	if ResourceSaver.save(def, path) == OK:
		current_file_path = path
		_update_file_label()

func _on_save_file_selected(path: String) -> void:
	if not path.ends_with(".tres"):
		path += ".tres"
	_save_to_path(path)

func _on_open_file_selected(path: String) -> void:
	_load_from_path(path)

func _load_from_path(path: String) -> void:
	if not ResourceLoader.exists(path):
		return
	var def := ResourceLoader.load(path) as VoxelDefinition
	if not def:
		return
	edit_mode = def.edit_mode
	grid_x = def.grid_x
	grid_y = def.grid_y
	grid_z = def.grid_z
	cells = def.to_cells()
	current_file_path = path
	_cancel_box()
	place_cell = Vector3i(-1, -1, -1)
	target_cell = Vector3i(-1, -1, -1)
	cursor_mesh_instance.visible = false
	floor_y = 0
	floor_slider.max_value = grid_y - 1
	floor_slider.set_value_no_signal(0)
	floor_value_label.text = "Y = 0"
	var buttons := mode_group.get_buttons()
	buttons[0].button_pressed = edit_mode == EditMode.BLOCK
	buttons[1].button_pressed = edit_mode == EditMode.CHARACTER
	_rebuild_mesh()
	_rebuild_grid()
	_center_camera()
	_update_file_label()

func _update_file_label() -> void:
	file_label.text = "File: " + (current_file_path.get_file() if not current_file_path.is_empty() else "(unsaved)")

# ─── Mesh Building ───

func _rebuild_mesh() -> void:
	var new_mesh := BlockMeshBuilder.build_mesh(cells, grid_x, grid_y, grid_z, CELL_SIZE)
	mesh_instance.mesh = new_mesh
	if new_mesh and new_mesh.get_surface_count() > 0:
		var shape := ConcavePolygonShape3D.new()
		shape.backface_collision = true
		shape.set_faces(new_mesh.get_faces())
		collision_shape.shape = shape
	else:
		collision_shape.shape = null

func _rebuild_grid() -> void:
	var im := ImmediateMesh.new()
	var wx := grid_x * CELL_SIZE
	var wy := grid_y * CELL_SIZE
	var wz := grid_z * CELL_SIZE
	var fy := floor_y * CELL_SIZE

	# Floor grid at current floor_y
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in range(grid_x + 1):
		var t := i * CELL_SIZE
		im.surface_add_vertex(Vector3(t, fy, 0))
		im.surface_add_vertex(Vector3(t, fy, wz))
	for i in range(grid_z + 1):
		var t := i * CELL_SIZE
		im.surface_add_vertex(Vector3(0, fy, t))
		im.surface_add_vertex(Vector3(wx, fy, t))
	im.surface_end()

	# Bounding box edges
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	var c: Array[Vector3] = [
		Vector3(0, 0, 0), Vector3(wx, 0, 0), Vector3(wx, 0, wz), Vector3(0, 0, wz),
		Vector3(0, wy, 0), Vector3(wx, wy, 0), Vector3(wx, wy, wz), Vector3(0, wy, wz),
	]
	for e in [[0,1],[1,2],[2,3],[3,0],[4,5],[5,6],[6,7],[7,4],[0,4],[1,5],[2,6],[3,7]]:
		im.surface_add_vertex(c[e[0]])
		im.surface_add_vertex(c[e[1]])
	im.surface_end()

	grid_mesh_instance.mesh = im

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.7, 1.0, 0.35)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	grid_mesh_instance.material_override = mat
