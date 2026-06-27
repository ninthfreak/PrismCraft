extends Node3D

enum EditMode { BLOCK, CHARACTER }

const CELL_RES := 32
const CELL_SIZE := 1.0 / CELL_RES

var edit_mode: int = EditMode.BLOCK
var grid_x := 32
var grid_y := 32
var grid_z := 32

var cells: Array = []
var current_type: int = CellTypes.Type.SOLID
var current_orientation: int = 0
var current_color: int = 0
var current_file_path := ""

var mesh_instance: MeshInstance3D
var collision_body: StaticBody3D
var collision_shape: CollisionShape3D
var grid_mesh_instance: MeshInstance3D
var cursor_mesh_instance: MeshInstance3D
var cursor_cell := Vector3i(-1, -1, -1)

var ui_layer: CanvasLayer
var tool_label: Label
var coord_label: Label
var help_label: Label
var mode_label: Label
var file_label: Label

var save_dialog: FileDialog
var open_dialog: FileDialog

@onready var camera: Camera3D = $Camera3D

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
	if not FileAccess.file_exists("res://definitions/male.tres"):
		var male := VoxelDefinition.create_male()
		ResourceSaver.save(male, "res://definitions/male.tres")
	if not FileAccess.file_exists("res://definitions/female.tres"):
		var female := VoxelDefinition.create_female()
		ResourceSaver.save(female, "res://definitions/female.tres")

func _center_camera() -> void:
	var world_size := Vector3(grid_x, grid_y, grid_z) * CELL_SIZE
	camera.pivot = world_size * 0.5

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

func _setup_scene() -> void:
	mesh_instance = MeshInstance3D.new()
	add_child(mesh_instance)

	collision_body = StaticBody3D.new()
	add_child(collision_body)
	collision_shape = CollisionShape3D.new()
	collision_body.add_child(collision_shape)

	grid_mesh_instance = MeshInstance3D.new()
	add_child(grid_mesh_instance)

	cursor_mesh_instance = MeshInstance3D.new()
	add_child(cursor_mesh_instance)
	cursor_mesh_instance.visible = false

	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mesh_instance.material_override = mat

func _setup_ui() -> void:
	ui_layer = CanvasLayer.new()
	add_child(ui_layer)

	mode_label = Label.new()
	mode_label.position = Vector2(10, 10)
	mode_label.add_theme_font_size_override("font_size", 18)
	ui_layer.add_child(mode_label)

	tool_label = Label.new()
	tool_label.position = Vector2(10, 35)
	tool_label.add_theme_font_size_override("font_size", 16)
	ui_layer.add_child(tool_label)

	coord_label = Label.new()
	coord_label.position = Vector2(10, 58)
	coord_label.add_theme_font_size_override("font_size", 14)
	ui_layer.add_child(coord_label)

	file_label = Label.new()
	file_label.position = Vector2(10, 80)
	file_label.add_theme_font_size_override("font_size", 13)
	ui_layer.add_child(file_label)

	help_label = Label.new()
	help_label.position = Vector2(10, 640)
	help_label.add_theme_font_size_override("font_size", 11)
	help_label.text = "LMB: Place | RMB: Remove | RMB-drag: Orbit | MMB-drag: Pan | Scroll: Zoom\nTab: Type | Q/E: Rotate | 1-8: Color | M: Mode | Ctrl+S: Save | Ctrl+O: Open | Ctrl+N: New"
	ui_layer.add_child(help_label)

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

	_update_mode_label()
	_update_tool_label()
	_update_file_label()

func _update_mode_label() -> void:
	var mode_name := "BLOCK (32x32x32)" if edit_mode == EditMode.BLOCK else "CHARACTER (32x32x64)"
	mode_label.text = "Mode: " + mode_name

func _update_tool_label() -> void:
	var type_name := "SOLID" if current_type == CellTypes.Type.SOLID else "PRISM"
	var orient_str := ""
	if current_type == CellTypes.Type.PRISM:
		orient_str = " | Orient: " + CellTypes.get_orientation_name(current_orientation)
	tool_label.text = "Tool: %s%s | Color: %s" % [type_name, orient_str, CellTypes.PALETTE_NAMES[current_color]]

func _update_file_label() -> void:
	if current_file_path.is_empty():
		file_label.text = "File: (unsaved)"
	else:
		file_label.text = "File: " + current_file_path

func _set_edit_mode(mode: int) -> void:
	if mode == edit_mode:
		return
	edit_mode = mode
	if edit_mode == EditMode.BLOCK:
		grid_x = 32
		grid_y = 32
		grid_z = 32
	else:
		grid_x = 32
		grid_y = 64
		grid_z = 32
	cursor_cell = Vector3i(-1, -1, -1)
	cursor_mesh_instance.visible = false
	current_file_path = ""
	_init_cells()
	_rebuild_mesh()
	_rebuild_grid()
	_center_camera()
	_update_mode_label()
	_update_file_label()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.ctrl_pressed:
			match event.keycode:
				KEY_S:
					_save()
					get_viewport().set_input_as_handled()
					return
				KEY_O:
					_open()
					get_viewport().set_input_as_handled()
					return
				KEY_N:
					_new()
					get_viewport().set_input_as_handled()
					return

		match event.keycode:
			KEY_TAB:
				if current_type == CellTypes.Type.SOLID:
					current_type = CellTypes.Type.PRISM
				else:
					current_type = CellTypes.Type.SOLID
				_update_tool_label()
				_update_cursor()
				get_viewport().set_input_as_handled()
			KEY_Q:
				current_orientation = (current_orientation - 1) % 12
				if current_orientation < 0:
					current_orientation += 12
				_update_tool_label()
				_update_cursor()
			KEY_E:
				current_orientation = (current_orientation + 1) % 12
				_update_tool_label()
				_update_cursor()
			KEY_M:
				if edit_mode == EditMode.BLOCK:
					_set_edit_mode(EditMode.CHARACTER)
				else:
					_set_edit_mode(EditMode.BLOCK)
			KEY_1: _set_color(0)
			KEY_2: _set_color(1)
			KEY_3: _set_color(2)
			KEY_4: _set_color(3)
			KEY_5: _set_color(4)
			KEY_6: _set_color(5)
			KEY_7: _set_color(6)
			KEY_8: _set_color(7)

	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_try_place()
		if not event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			if camera and not camera.was_orbit_drag():
				_try_remove()

	if event is InputEventMouseMotion:
		_update_raycast()

func _set_color(idx: int) -> void:
	current_color = idx
	_update_tool_label()

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
	cursor_cell = Vector3i(-1, -1, -1)
	cursor_mesh_instance.visible = false
	_init_cells()
	_rebuild_mesh()
	_update_file_label()

func _save_to_path(path: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var def := VoxelDefinition.new()
	def.set_from_cells(cells, grid_x, grid_y, grid_z, edit_mode)
	var err := ResourceSaver.save(def, path)
	if err == OK:
		current_file_path = path
		_update_file_label()
	else:
		push_error("Failed to save: " + str(err))

func _on_save_file_selected(path: String) -> void:
	if not path.ends_with(".tres"):
		path += ".tres"
	_save_to_path(path)

func _on_open_file_selected(path: String) -> void:
	_load_from_path(path)

func _load_from_path(path: String) -> void:
	if not ResourceLoader.exists(path):
		push_error("File not found: " + path)
		return
	var def := ResourceLoader.load(path) as VoxelDefinition
	if not def:
		push_error("Invalid VoxelDefinition: " + path)
		return

	edit_mode = def.edit_mode
	grid_x = def.grid_x
	grid_y = def.grid_y
	grid_z = def.grid_z
	cells = def.to_cells()
	current_file_path = path

	cursor_cell = Vector3i(-1, -1, -1)
	cursor_mesh_instance.visible = false
	_rebuild_mesh()
	_rebuild_grid()
	_center_camera()
	_update_mode_label()
	_update_file_label()

func _update_raycast() -> void:
	if not camera:
		return

	var mouse_pos := get_viewport().get_mouse_position()
	var from := camera.project_ray_origin(mouse_pos)
	var dir := camera.project_ray_normal(mouse_pos)

	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, from + dir * 100.0)
	var result := space.intersect_ray(query)

	if result:
		var hit_pos: Vector3 = result["position"]
		var hit_normal: Vector3 = result["normal"]
		var cell_pos := _world_to_cell(hit_pos - hit_normal * 0.01)
		if _in_bounds(cell_pos):
			cursor_cell = cell_pos
			_update_cursor()
			return

	if dir.y < -0.001:
		var t := -from.y / dir.y
		if t > 0:
			var hit := from + dir * t
			var cell_pos := _world_to_cell(hit)
			if _in_bounds(cell_pos):
				cursor_cell = cell_pos
				_update_cursor()
				return

	cursor_cell = Vector3i(-1, -1, -1)
	cursor_mesh_instance.visible = false
	coord_label.text = ""

func _world_to_cell(world_pos: Vector3) -> Vector3i:
	return Vector3i(
		int(floor(world_pos.x / CELL_SIZE)),
		int(floor(world_pos.y / CELL_SIZE)),
		int(floor(world_pos.z / CELL_SIZE))
	)

func _in_bounds(pos: Vector3i) -> bool:
	return pos.x >= 0 and pos.x < grid_x and pos.y >= 0 and pos.y < grid_y and pos.z >= 0 and pos.z < grid_z

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

func _update_cursor() -> void:
	if not _in_bounds(cursor_cell):
		cursor_mesh_instance.visible = false
		coord_label.text = ""
		return

	var margin := CELL_SIZE * 0.02
	var pos := Vector3(cursor_cell) * CELL_SIZE - Vector3.ONE * margin
	var size := CELL_SIZE + margin * 2.0

	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)

	if current_type == CellTypes.Type.SOLID:
		var corners: Array[Vector3] = [
			pos,
			pos + Vector3(size, 0, 0),
			pos + Vector3(size, 0, size),
			pos + Vector3(0, 0, size),
			pos + Vector3(0, size, 0),
			pos + Vector3(size, size, 0),
			pos + Vector3(size, size, size),
			pos + Vector3(0, size, size),
		]
		var edges := [
			[0,1],[1,2],[2,3],[3,0],
			[4,5],[5,6],[6,7],[7,4],
			[0,4],[1,5],[2,6],[3,7],
		]
		for e in edges:
			im.surface_add_vertex(corners[e[0]])
			im.surface_add_vertex(corners[e[1]])
	else:
		var verts := _get_prism_vertices(pos, size, current_orientation)
		var p_near: Array = verts[0]
		var p_far: Array = verts[1]

		for i in range(3):
			im.surface_add_vertex(p_near[i])
			im.surface_add_vertex(p_near[(i + 1) % 3])
		for i in range(3):
			im.surface_add_vertex(p_far[i])
			im.surface_add_vertex(p_far[(i + 1) % 3])
		for i in range(3):
			im.surface_add_vertex(p_near[i])
			im.surface_add_vertex(p_far[i])

	im.surface_end()

	cursor_mesh_instance.mesh = im
	cursor_mesh_instance.visible = true

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color.WHITE
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	cursor_mesh_instance.material_override = mat

	coord_label.text = "Cell: (%d, %d, %d)" % [cursor_cell.x, cursor_cell.y, cursor_cell.z]

func _try_place() -> void:
	if not _in_bounds(cursor_cell):
		return

	if not camera:
		return

	var mouse_pos := get_viewport().get_mouse_position()
	var from := camera.project_ray_origin(mouse_pos)
	var dir := camera.project_ray_normal(mouse_pos)

	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, from + dir * 100.0)
	var result := space.intersect_ray(query)

	var place_cell := cursor_cell

	if result:
		var hit_pos: Vector3 = result["position"]
		var hit_normal: Vector3 = result["normal"]
		var adjacent := _world_to_cell(hit_pos + hit_normal * 0.01)
		if _in_bounds(adjacent) and cells[adjacent.x][adjacent.y][adjacent.z][0] == CellTypes.Type.EMPTY:
			place_cell = adjacent

	if cells[place_cell.x][place_cell.y][place_cell.z][0] != CellTypes.Type.EMPTY:
		if _in_bounds(cursor_cell) and cells[cursor_cell.x][cursor_cell.y][cursor_cell.z][0] == CellTypes.Type.EMPTY:
			place_cell = cursor_cell
		else:
			return

	cells[place_cell.x][place_cell.y][place_cell.z] = [current_type, current_orientation, current_color]
	_rebuild_mesh()

func _try_remove() -> void:
	if not camera:
		return

	var mouse_pos := get_viewport().get_mouse_position()
	var from := camera.project_ray_origin(mouse_pos)
	var dir := camera.project_ray_normal(mouse_pos)

	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, from + dir * 100.0)
	var result := space.intersect_ray(query)

	if result:
		var hit_pos: Vector3 = result["position"]
		var hit_normal: Vector3 = result["normal"]
		var cell_pos := _world_to_cell(hit_pos - hit_normal * 0.01)
		if _in_bounds(cell_pos) and cells[cell_pos.x][cell_pos.y][cell_pos.z][0] != CellTypes.Type.EMPTY:
			cells[cell_pos.x][cell_pos.y][cell_pos.z] = [CellTypes.Type.EMPTY, 0, 0]
			_rebuild_mesh()

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

	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in range(grid_x + 1):
		var t := i * CELL_SIZE
		im.surface_add_vertex(Vector3(t, 0, 0))
		im.surface_add_vertex(Vector3(t, 0, wz))
	for i in range(grid_z + 1):
		var t := i * CELL_SIZE
		im.surface_add_vertex(Vector3(0, 0, t))
		im.surface_add_vertex(Vector3(wx, 0, t))
	im.surface_end()

	im.surface_begin(Mesh.PRIMITIVE_LINES)
	var box_corners: Array[Vector3] = [
		Vector3(0, 0, 0), Vector3(wx, 0, 0), Vector3(wx, 0, wz), Vector3(0, 0, wz),
		Vector3(0, wy, 0), Vector3(wx, wy, 0), Vector3(wx, wy, wz), Vector3(0, wy, wz),
	]
	var box_edges := [
		[4,5],[5,6],[6,7],[7,4],
		[0,4],[1,5],[2,6],[3,7],
	]
	for e in box_edges:
		im.surface_add_vertex(box_corners[e[0]])
		im.surface_add_vertex(box_corners[e[1]])
	im.surface_end()

	grid_mesh_instance.mesh = im

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1, 1, 1, 0.3)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	grid_mesh_instance.material_override = mat
