class_name BlockMeshBuilder

static func _add_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, normal: Vector3, color: Color) -> void:
	st.set_normal(normal)
	st.set_color(color)
	var cross_prod := (b - a).cross(c - a)
	if cross_prod.dot(normal) > 0:
		st.add_vertex(a)
		st.add_vertex(b)
		st.add_vertex(c)
	else:
		st.add_vertex(a)
		st.add_vertex(c)
		st.add_vertex(b)

static func _add_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3, color: Color) -> void:
	_add_tri(st, a, b, c, normal, color)
	_add_tri(st, a, c, d, normal, color)

static func build_mesh(cells: Array, grid_size: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var cell_size := 1.0 / grid_size

	for x in range(grid_size):
		for y in range(grid_size):
			for z in range(grid_size):
				var cell: Array = cells[x][y][z]
				var cell_type: int = cell[0]
				if cell_type == CellTypes.Type.EMPTY:
					continue

				var origin := Vector3(x, y, z) * cell_size
				var color: Color = CellTypes.PALETTE[cell[2]]

				if cell_type == CellTypes.Type.SOLID:
					_build_cube(st, cells, grid_size, x, y, z, origin, cell_size, color)
				elif cell_type == CellTypes.Type.PRISM:
					_build_prism(st, origin, cell_size, cell[1], color)

	st.generate_tangents()
	return st.commit()

static func _is_solid_neighbor(cells: Array, grid_size: int, x: int, y: int, z: int) -> bool:
	if x < 0 or x >= grid_size or y < 0 or y >= grid_size or z < 0 or z >= grid_size:
		return false
	return cells[x][y][z][0] == CellTypes.Type.SOLID

static func _build_cube(st: SurfaceTool, cells: Array, grid_size: int, cx: int, cy: int, cz: int, o: Vector3, s: float, color: Color) -> void:
	# +Y top
	if not _is_solid_neighbor(cells, grid_size, cx, cy + 1, cz):
		_add_quad(st,
			o + Vector3(0, s, 0), o + Vector3(s, s, 0),
			o + Vector3(s, s, s), o + Vector3(0, s, s),
			Vector3.UP, color)
	# -Y bottom
	if not _is_solid_neighbor(cells, grid_size, cx, cy - 1, cz):
		_add_quad(st,
			o + Vector3(0, 0, s), o + Vector3(s, 0, s),
			o + Vector3(s, 0, 0), o + Vector3(0, 0, 0),
			Vector3.DOWN, color)
	# +X right
	if not _is_solid_neighbor(cells, grid_size, cx + 1, cy, cz):
		_add_quad(st,
			o + Vector3(s, 0, 0), o + Vector3(s, s, 0),
			o + Vector3(s, s, s), o + Vector3(s, 0, s),
			Vector3.RIGHT, color)
	# -X left
	if not _is_solid_neighbor(cells, grid_size, cx - 1, cy, cz):
		_add_quad(st,
			o + Vector3(0, 0, s), o + Vector3(0, s, s),
			o + Vector3(0, s, 0), o + Vector3(0, 0, 0),
			Vector3.LEFT, color)
	# +Z front
	if not _is_solid_neighbor(cells, grid_size, cx, cy, cz + 1):
		_add_quad(st,
			o + Vector3(0, 0, s), o + Vector3(0, s, s),
			o + Vector3(s, s, s), o + Vector3(s, 0, s),
			Vector3.BACK, color)
	# -Z back
	if not _is_solid_neighbor(cells, grid_size, cx, cy, cz - 1):
		_add_quad(st,
			o + Vector3(s, 0, 0), o + Vector3(s, s, 0),
			o + Vector3(0, s, 0), o + Vector3(0, 0, 0),
			Vector3.FORWARD, color)

static func _build_prism(st: SurfaceTool, o: Vector3, s: float, orientation: int, color: Color) -> void:
	var axis: int = orientation / 4
	var corner: int = orientation % 4

	# 2D triangle corners in face-local space (u, v)
	# corner determines which corner of the unit square has the right angle
	var tri_2d: Array[Vector2]
	match corner:
		0: # SW - right angle at (0,0)
			tri_2d = [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1)]
		1: # SE - right angle at (1,0)
			tri_2d = [Vector2(1, 0), Vector2(1, 1), Vector2(0, 0)]
		2: # NE - right angle at (1,1)
			tri_2d = [Vector2(1, 1), Vector2(0, 1), Vector2(1, 0)]
		3: # NW - right angle at (0,1)
			tri_2d = [Vector2(0, 1), Vector2(0, 0), Vector2(1, 1)]

	# Map 2D face coords to 3D based on axis
	# axis 0 = Y (triangle in XZ plane, extruded along Y)
	# axis 1 = X (triangle in YZ plane, extruded along X)
	# axis 2 = Z (triangle in XY plane, extruded along Z)
	var p_near: Array[Vector3] = []
	var p_far: Array[Vector3] = []

	for uv in tri_2d:
		var near: Vector3
		var far: Vector3
		match axis:
			0: # Y-axis: face is XZ, extrude along Y
				near = o + Vector3(uv.x * s, 0, uv.y * s)
				far = o + Vector3(uv.x * s, s, uv.y * s)
			1: # X-axis: face is YZ, extrude along X
				near = o + Vector3(0, uv.x * s, uv.y * s)
				far = o + Vector3(s, uv.x * s, uv.y * s)
			2: # Z-axis: face is XY, extrude along Z
				near = o + Vector3(uv.x * s, uv.y * s, 0)
				far = o + Vector3(uv.x * s, uv.y * s, s)
		p_near.append(near)
		p_far.append(far)

	# Axis direction for computing side normals
	var axis_dir: Vector3
	match axis:
		0: axis_dir = Vector3.UP
		1: axis_dir = Vector3.RIGHT
		2: axis_dir = Vector3.BACK

	# Near cap (triangle)
	var near_normal := -axis_dir
	_add_tri(st, p_near[0], p_near[1], p_near[2], near_normal, color)

	# Far cap (triangle)
	var far_normal := axis_dir
	_add_tri(st, p_far[0], p_far[1], p_far[2], far_normal, color)

	# 3 side faces (rectangles connecting near edge to far edge)
	for i in range(3):
		var j := (i + 1) % 3
		var a := p_near[i]
		var b := p_near[j]
		var c := p_far[j]
		var d := p_far[i]

		# Compute outward normal for this side
		var edge := (b - a).normalized()
		var side_normal := edge.cross(axis_dir).normalized()

		# Make sure normal points outward (away from the third vertex)
		var third := p_near[(i + 2) % 3]
		var to_third := (third - a).normalized()
		if side_normal.dot(to_third) > 0:
			side_normal = -side_normal

		_add_quad(st, a, b, c, d, side_normal, color)
