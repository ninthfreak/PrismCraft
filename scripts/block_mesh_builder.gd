class_name BlockMeshBuilder

static func _add_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, normal: Vector3, color: Color) -> void:
	st.set_normal(normal)
	st.set_color(color)
	var cross_prod := (b - a).cross(c - a)
	if cross_prod.dot(normal) < 0:
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

static func build_mesh(cells: Array, gx: int, gy: int, gz: int, cell_size: float) -> ArrayMesh:
	var st_opaque := SurfaceTool.new()
	st_opaque.begin(Mesh.PRIMITIVE_TRIANGLES)
	var st_cutout := SurfaceTool.new()
	st_cutout.begin(Mesh.PRIMITIVE_TRIANGLES)
	var has_cutout := false

	for x in range(gx):
		for y in range(gy):
			for z in range(gz):
				var cell: Array = cells[x][y][z]
				var cell_type: int = cell[0]
				if cell_type == CellTypes.Type.EMPTY:
					continue

				var origin := Vector3(x, y, z) * cell_size

				if cell_type == CellTypes.Type.SOLID:
					if CellTypes.is_cutout_cell(cell):
						_build_cube(st_cutout, cells, gx, gy, gz, x, y, z, origin, cell_size, cell, true)
						has_cutout = true
					else:
						_build_cube(st_opaque, cells, gx, gy, gz, x, y, z, origin, cell_size, cell, false)
				elif cell_type == CellTypes.Type.PRISM:
					if CellTypes.is_rgb5551(cell[2]):
						_build_prism(st_cutout, origin, cell_size, cell[1], CellTypes.decode_color(cell[2]))
						has_cutout = true
					else:
						_build_prism(st_opaque, origin, cell_size, cell[1], CellTypes.decode_color(cell[2]))

	var mesh := st_opaque.commit()

	if has_cutout:
		st_cutout.commit(mesh)

	return mesh

static func _is_opaque_solid(cells: Array, gx: int, gy: int, gz: int, x: int, y: int, z: int) -> bool:
	if x < 0 or x >= gx or y < 0 or y >= gy or z < 0 or z >= gz:
		return false
	var cell: Array = cells[x][y][z]
	return cell[0] == CellTypes.Type.SOLID and not CellTypes.is_cutout_cell(cell)

static func _build_cube(st: SurfaceTool, cells: Array, gx: int, gy: int, gz: int, cx: int, cy: int, cz: int, o: Vector3, s: float, cell: Array, is_cutout: bool) -> void:
	var dirs := [
		[0, 1, 0, CellTypes.FACE_TOP, Vector3.UP],
		[0, -1, 0, CellTypes.FACE_BOTTOM, Vector3.DOWN],
		[1, 0, 0, CellTypes.FACE_RIGHT, Vector3.RIGHT],
		[-1, 0, 0, CellTypes.FACE_LEFT, Vector3.LEFT],
		[0, 0, 1, CellTypes.FACE_FRONT, Vector3.BACK],
		[0, 0, -1, CellTypes.FACE_BACK, Vector3.FORWARD],
	]
	var quads := [
		[Vector3(0, s, 0), Vector3(s, s, 0), Vector3(s, s, s), Vector3(0, s, s)],
		[Vector3(0, 0, s), Vector3(s, 0, s), Vector3(s, 0, 0), Vector3(0, 0, 0)],
		[Vector3(s, 0, 0), Vector3(s, s, 0), Vector3(s, s, s), Vector3(s, 0, s)],
		[Vector3(0, 0, s), Vector3(0, s, s), Vector3(0, s, 0), Vector3(0, 0, 0)],
		[Vector3(0, 0, s), Vector3(0, s, s), Vector3(s, s, s), Vector3(s, 0, s)],
		[Vector3(s, 0, 0), Vector3(s, s, 0), Vector3(0, s, 0), Vector3(0, 0, 0)],
	]

	for i in range(6):
		var d: Array = dirs[i]
		var face_color_val: int = cell[d[3]]
		var color := CellTypes.decode_color(face_color_val)
		if CellTypes.is_rgb5551(face_color_val) and color.a < CellTypes.ALPHA_THRESHOLD:
			continue
		var nx: int = cx + d[0]
		var ny: int = cy + d[1]
		var nz: int = cz + d[2]
		if _is_opaque_solid(cells, gx, gy, gz, nx, ny, nz):
			continue
		if not is_cutout and nx >= 0 and nx < gx and ny >= 0 and ny < gy and nz >= 0 and nz < gz:
			var ncell: Array = cells[nx][ny][nz]
			if ncell[0] == CellTypes.Type.SOLID and not CellTypes.is_cutout_cell(ncell):
				continue
		var q: Array = quads[i]
		var normal: Vector3 = d[4]
		_add_quad(st, o + q[0], o + q[1], o + q[2], o + q[3], normal, color)

static func _build_prism(st: SurfaceTool, o: Vector3, s: float, orientation: int, color: Color) -> void:
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
		var near: Vector3
		var far: Vector3
		match axis:
			0:
				near = o + Vector3(uv.x * s, 0, uv.y * s)
				far = o + Vector3(uv.x * s, s, uv.y * s)
			1:
				near = o + Vector3(0, uv.x * s, uv.y * s)
				far = o + Vector3(s, uv.x * s, uv.y * s)
			_:
				near = o + Vector3(uv.x * s, uv.y * s, 0)
				far = o + Vector3(uv.x * s, uv.y * s, s)
		p_near.append(near)
		p_far.append(far)

	var axis_dir: Vector3
	match axis:
		0: axis_dir = Vector3.UP
		1: axis_dir = Vector3.RIGHT
		_: axis_dir = Vector3.BACK

	var near_normal := -axis_dir
	_add_tri(st, p_near[0], p_near[1], p_near[2], near_normal, color)

	var far_normal := axis_dir
	_add_tri(st, p_far[0], p_far[1], p_far[2], far_normal, color)

	for i in range(3):
		var j := (i + 1) % 3
		var a := p_near[i]
		var b := p_near[j]
		var c := p_far[j]
		var d := p_far[i]

		var edge := (b - a).normalized()
		var side_normal := edge.cross(axis_dir).normalized()

		var third := p_near[(i + 2) % 3]
		if side_normal.dot(third - a) > 0:
			side_normal = -side_normal

		_add_quad(st, a, b, c, d, side_normal, color)
