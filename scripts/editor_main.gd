extends Node3D

const GRID_SIZE := 8

var cells: Array = []
var current_type: int = CellTypes.Type.SOLID
var current_orientation: int = 0
var current_color: int = 0

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

func _ready() -> void:
	_init_cells()
	_setup_scene()
	_setup_ui()
	_rebuild_mesh()
	_rebuild_grid()

func _init_cells() -> void:
	cells.resize(GRID_SIZE)
	for x in range(GRID_SIZE):
		cells[x] = []
		cells[x].resize(GRID_SIZE)
		for y in range(GRID_SIZE):
			cells[x][y] = []
			cells[x][y].resize(GRID_SIZE)
			for z in range(GRID_SIZE):
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

	tool_label = Label.new()
	tool_label.position = Vector2(10, 10)
	tool_label.add_theme_font_size_override("font_size", 16)
	ui_layer.add_child(tool_label)

	coord_label = Label.new()
	coord_label.position = Vector2(10, 35)
	coord_label.add_theme_font_size_override("font_size", 14)
	ui_layer.add_child(coord_label)

	help_label = Label.new()
	help_label.position = Vector2(10, 660)
	help_label.add_theme_font_size_override("font_size", 12)
	help_label.text = "LMB: Place | MMB: Remove | RMB-drag: Orbit | Scroll: Zoom | Tab: Type | Q/E: Rotate | 1-8: Color"
	ui_layer.add_child(help_label)

	_update_tool_label()

func _update_tool_label() -> void:
	var type_name := "SOLID" if current_type == CellTypes.Type.SOLID else "PRISM"
	var orient_str := ""
	if current_type == CellTypes.Type.PRISM:
		orient_str = " | Orient: " + CellTypes.get_orientation_name(current_orientation)
	tool_label.text = "Tool: %s%s | Color: %s" % [type_name, orient_str, CellTypes.PALETTE_NAMES[current_color]]

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
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
			KEY_1: _set_color(0)
			KEY_2: _set_color(1)
			KEY_3: _set_color(2)
			KEY_4: _set_color(3)
			KEY_5: _set_color(4)
			KEY_6: _set_color(5)
			KEY_7: _set_color(6)
			KEY_8: _set_color(7)

	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				_try_place()
			MOUSE_BUTTON_MIDDLE:
				_try_remove()

	if event is InputEventMouseMotion:
		_update_raycast()

func _set_color(idx: int) -> void:
	current_color = idx
	_update_tool_label()

func _update_raycast() -> void:
	var camera := get_viewport().get_camera_3d()
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

	# Floor plane fallback (y = 0)
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
	var cell_size := 1.0 / GRID_SIZE
	return Vector3i(
		int(floor(world_pos.x / cell_size)),
		int(floor(world_pos.y / cell_size)),
		int(floor(world_pos.z / cell_size))
	)

func _in_bounds(pos: Vector3i) -> bool:
	return pos.x >= 0 and pos.x < GRID_SIZE and pos.y >= 0 and pos.y < GRID_SIZE and pos.z >= 0 and pos.z < GRID_SIZE

func _update_cursor() -> void:
	if not _in_bounds(cursor_cell):
		cursor_mesh_instance.visible = false
		coord_label.text = ""
		return

	var cell_size := 1.0 / GRID_SIZE
	var margin := cell_size * 0.02
	var pos := Vector3(cursor_cell) * cell_size - Vector3.ONE * margin
	var size := cell_size + margin * 2.0

	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)

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

	var camera := get_viewport().get_camera_3d()
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
		# If clicking floor with no mesh, place at cursor
		if _in_bounds(cursor_cell) and cells[cursor_cell.x][cursor_cell.y][cursor_cell.z][0] == CellTypes.Type.EMPTY:
			place_cell = cursor_cell
		else:
			return

	cells[place_cell.x][place_cell.y][place_cell.z] = [current_type, current_orientation, current_color]
	_rebuild_mesh()

func _try_remove() -> void:
	var camera := get_viewport().get_camera_3d()
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
	var new_mesh := BlockMeshBuilder.build_mesh(cells, GRID_SIZE)
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
	var cell_size := 1.0 / GRID_SIZE

	# Bottom grid lines
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in range(GRID_SIZE + 1):
		var t := i * cell_size
		# X-parallel lines
		im.surface_add_vertex(Vector3(t, 0, 0))
		im.surface_add_vertex(Vector3(t, 0, 1))
		# Z-parallel lines
		im.surface_add_vertex(Vector3(0, 0, t))
		im.surface_add_vertex(Vector3(1, 0, t))
	im.surface_end()

	# Outer box edges
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	var box_corners: Array[Vector3] = [
		Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, 1), Vector3(0, 0, 1),
		Vector3(0, 1, 0), Vector3(1, 1, 0), Vector3(1, 1, 1), Vector3(0, 1, 1),
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
