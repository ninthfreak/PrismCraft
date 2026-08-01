class_name BlockMeshBuilder

# Viewport-only display colour. Models carry no colour of their own; this exists
# purely so the editor is not black-on-black, and it never reaches the exporter.
const DISPLAY := Color(0.62, 0.64, 0.68)

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

static func build_mesh(cells: Array, gx: int, gy: int, gz: int, cell_size: float, ceiling_y: int = -1, ceil_axis: int = 1) -> ArrayMesh:
	return build_chunk_mesh(cells, gx, gy, gz, 0, 0, 0, gx, gy, gz, cell_size, ceiling_y, ceil_axis)

static func build_chunk_mesh(cells: Array, gx: int, gy: int, gz: int, x0: int, y0: int, z0: int, x1: int, y1: int, z1: int, cell_size: float, ceiling_y: int = -1, ceil_axis: int = 1) -> ArrayMesh:
	var st_opaque := SurfaceTool.new()
	st_opaque.begin(Mesh.PRIMITIVE_TRIANGLES)

	for x in range(x0, x1):
		for y in range(y0, y1):
			for z in range(z0, z1):
				var cell: Array = cells[x][y][z]
				var cell_type: int = cell[0]
				if cell_type == CellTypes.Type.EMPTY:
					continue

				var origin := Vector3(x, y, z) * cell_size

				if cell_type == CellTypes.Type.SOLID:
					_build_cube(st_opaque, cells, gx, gy, gz, x, y, z, origin, cell_size, ceiling_y, ceil_axis)
				elif cell_type == CellTypes.Type.PRISM:
					var ori: int = cell[1]
					var pax: int = ori / 4
					var near_cap := true
					var far_cap := true
					var nnx: int = x; var nny: int = y; var nnz: int = z
					var fnx: int = x; var fny: int = y; var fnz: int = z
					match pax:
						0: nny = y - 1; fny = y + 1
						1: nnx = x - 1; fnx = x + 1
						_: nnz = z - 1; fnz = z + 1
					if nnx >= 0 and nny >= 0 and nnz >= 0:
						var nc: Array = cells[nnx][nny][nnz]
						if nc[0] == CellTypes.Type.PRISM and nc[1] == ori:
							near_cap = false
					if fnx < gx and fny < gy and fnz < gz:
						var nc: Array = cells[fnx][fny][fnz]
						if nc[0] == CellTypes.Type.PRISM and nc[1] == ori:
							far_cap = false
					_build_prism(st_opaque, origin, cell_size, ori, near_cap, far_cap)

	var mesh := st_opaque.commit()


	return mesh

static func _build_cube(st: SurfaceTool, cells: Array, gx: int, gy: int, gz: int, cx: int, cy: int, cz: int, o: Vector3, s: float, ceiling_y: int = -1, ceil_axis: int = 1) -> void:
	var dirs := [
		[0, 1, 0, Vector3.UP],
		[0, -1, 0, Vector3.DOWN],
		[1, 0, 0, Vector3.RIGHT],
		[-1, 0, 0, Vector3.LEFT],
		[0, 0, 1, Vector3.BACK],
		[0, 0, -1, Vector3.FORWARD],
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
		# The +ceil_axis face at the ceiling layer is always exposed: everything
		# past the ceiling is clipped away by the shader, so the neighbor on that
		# side can't occlude it. Without this cap the revealed voxel shows a hole.
		var cell_depth: int = cx if ceil_axis == 0 else (cy if ceil_axis == 1 else cz)
		var is_cap_face: bool = d[ceil_axis] == 1
		var force_face: bool = is_cap_face and ceiling_y >= 0 and cell_depth == ceiling_y
		if not force_face:
			var nx: int = cx + d[0]
			var ny: int = cy + d[1]
			var nz: int = cz + d[2]
			if nx >= 0 and nx < gx and ny >= 0 and ny < gy and nz >= 0 and nz < gz:
				var ncell: Array = cells[nx][ny][nz]
				# A face between two solid cells is interior.
				if ncell[0] == CellTypes.Type.SOLID:
					continue
		var q: Array = quads[i]
		var normal: Vector3 = d[3]
		_add_quad(st, o + q[0], o + q[1], o + q[2], o + q[3], normal, DISPLAY)

static func _build_prism(st: SurfaceTool, o: Vector3, s: float, orientation: int, near_cap: bool = true, far_cap: bool = true) -> void:
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


	if near_cap:
		_add_tri(st, p_near[0], p_near[1], p_near[2], -axis_dir, DISPLAY)

	if far_cap:
		_add_tri(st, p_far[0], p_far[1], p_far[2], axis_dir, DISPLAY)

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

		_add_quad(st, a, b, c, d, side_normal, DISPLAY)
