class_name MeshExporter

static func export_obj(path: String, cells: Array, gx: int, gy: int, gz: int, cell_size: float) -> int:
	var s := cell_size
	var ox := gx * s / 2.0
	var oz := gz * s / 2.0
	var faces: Array = []

	for dir in range(6):
		_greedy_mesh_dir(cells, gx, gy, gz, s, ox, oz, dir, faces)

	_emit_prisms(cells, gx, gy, gz, s, ox, oz, faces)

	if faces.is_empty():
		return 0

	var verts: PackedVector3Array = []
	var norms: PackedVector3Array = []
	var face_defs: Array = []

	for face in faces:
		var n_idx := norms.size()
		norms.append(face[1])
		var v_start := verts.size()
		for v in face[2]:
			verts.append(v)
		face_defs.append([face[0], v_start, face[2].size(), n_idx])

	var mtl_file := path.get_file().get_basename() + ".mtl"
	var text := "mtllib " + mtl_file + "\n"

	for v in verts:
		text += "v %.6f %.6f %.6f\n" % [v.x, v.y, v.z]

	for n in norms:
		text += "vn %.4f %.4f %.4f\n" % [n.x, n.y, n.z]

	face_defs.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])

	var cur_color := -1
	var face_count := 0
	for fd in face_defs:
		if fd[0] != cur_color:
			cur_color = fd[0]
			text += "usemtl " + CellTypes.PALETTE_NAMES[cur_color].replace(" ", "_") + "\n"
		var vi: int = fd[1] + 1
		var ni: int = fd[3] + 1
		if fd[2] == 4:
			text += "f %d//%d %d//%d %d//%d %d//%d\n" % [vi, ni, vi + 1, ni, vi + 2, ni, vi + 3, ni]
		else:
			text += "f %d//%d %d//%d %d//%d\n" % [vi, ni, vi + 1, ni, vi + 2, ni]
		face_count += 1

	var file := FileAccess.open(path, FileAccess.WRITE)
	if not file:
		return 0
	file.store_string(text)
	file.close()

	var used_colors := {}
	for fd in face_defs:
		used_colors[fd[0]] = true

	var mtl_text := ""
	for ci in used_colors:
		var c: Color = CellTypes.PALETTE[ci]
		var cname: String = CellTypes.PALETTE_NAMES[ci].replace(" ", "_")
		mtl_text += "newmtl " + cname + "\n"
		mtl_text += "Kd %.4f %.4f %.4f\n" % [c.r, c.g, c.b]
		mtl_text += "Ka 0.1 0.1 0.1\n"
		mtl_text += "d 1.0\n\n"

	var mtl_path := path.get_base_dir().path_join(mtl_file)
	var mfile := FileAccess.open(mtl_path, FileAccess.WRITE)
	if mfile:
		mfile.store_string(mtl_text)
		mfile.close()

	return face_count

static func _greedy_mesh_dir(cells: Array, gx: int, gy: int, gz: int, s: float, ox: float, oz: float, dir: int, faces: Array) -> void:
	var slice_count: int
	var u_size: int
	var v_size: int

	match dir:
		0, 1:
			slice_count = gy; u_size = gx; v_size = gz
		2, 3:
			slice_count = gx; u_size = gz; v_size = gy
		_:
			slice_count = gz; u_size = gx; v_size = gy

	for slice in range(slice_count):
		var grid: Array = []
		grid.resize(u_size)
		for u in range(u_size):
			grid[u] = []
			grid[u].resize(v_size)
			for v in range(v_size):
				var cx: int; var cy: int; var cz: int
				match dir:
					0, 1: cx = u; cy = slice; cz = v
					2, 3: cx = slice; cy = v; cz = u
					_:    cx = u; cy = v; cz = slice

				if cells[cx][cy][cz][0] != CellTypes.Type.SOLID:
					grid[u][v] = -1
					continue

				var nx: int; var ny: int; var nz: int
				match dir:
					0: nx = cx; ny = cy + 1; nz = cz
					1: nx = cx; ny = cy - 1; nz = cz
					2: nx = cx + 1; ny = cy; nz = cz
					3: nx = cx - 1; ny = cy; nz = cz
					4: nx = cx; ny = cy; nz = cz + 1
					_: nx = cx; ny = cy; nz = cz - 1

				if nx < 0 or nx >= gx or ny < 0 or ny >= gy or nz < 0 or nz >= gz:
					grid[u][v] = cells[cx][cy][cz][2]
				elif cells[nx][ny][nz][0] == CellTypes.Type.EMPTY:
					grid[u][v] = cells[cx][cy][cz][2]
				else:
					grid[u][v] = -1

		var visited: Array = []
		visited.resize(u_size)
		for u in range(u_size):
			visited[u] = []
			visited[u].resize(v_size)
			for v in range(v_size):
				visited[u][v] = false

		for u in range(u_size):
			for v in range(v_size):
				if grid[u][v] == -1 or visited[u][v]:
					continue
				var color: int = grid[u][v]

				var w := 1
				while u + w < u_size and grid[u + w][v] == color and not visited[u + w][v]:
					w += 1

				var h := 1
				var can_extend := true
				while v + h < v_size and can_extend:
					for du in range(w):
						if grid[u + du][v + h] != color or visited[u + du][v + h]:
							can_extend = false
							break
					if can_extend:
						h += 1

				for du in range(w):
					for dv in range(h):
						visited[u + du][v + dv] = true

				var quad := _make_quad(dir, slice, u, v, w, h, s, ox, oz)
				faces.append([color, _dir_normal(dir), quad])

static func _dir_normal(dir: int) -> Vector3:
	match dir:
		0: return Vector3(0, 1, 0)
		1: return Vector3(0, -1, 0)
		2: return Vector3(1, 0, 0)
		3: return Vector3(-1, 0, 0)
		4: return Vector3(0, 0, 1)
		_: return Vector3(0, 0, -1)

static func _make_quad(dir: int, slice: int, u: int, v: int, w: int, h: int, s: float, ox: float, oz: float) -> Array:
	match dir:
		0:
			var y := (slice + 1) * s
			return [
				Vector3(u * s - ox, y, v * s - oz),
				Vector3(u * s - ox, y, (v + h) * s - oz),
				Vector3((u + w) * s - ox, y, (v + h) * s - oz),
				Vector3((u + w) * s - ox, y, v * s - oz),
			]
		1:
			var y := slice * s
			return [
				Vector3((u + w) * s - ox, y, v * s - oz),
				Vector3((u + w) * s - ox, y, (v + h) * s - oz),
				Vector3(u * s - ox, y, (v + h) * s - oz),
				Vector3(u * s - ox, y, v * s - oz),
			]
		2:
			var x := (slice + 1) * s - ox
			return [
				Vector3(x, v * s, u * s - oz),
				Vector3(x, (v + h) * s, u * s - oz),
				Vector3(x, (v + h) * s, (u + w) * s - oz),
				Vector3(x, v * s, (u + w) * s - oz),
			]
		3:
			var x := slice * s - ox
			return [
				Vector3(x, v * s, (u + w) * s - oz),
				Vector3(x, (v + h) * s, (u + w) * s - oz),
				Vector3(x, (v + h) * s, u * s - oz),
				Vector3(x, v * s, u * s - oz),
			]
		4:
			var z := (slice + 1) * s - oz
			return [
				Vector3((u + w) * s - ox, v * s, z),
				Vector3((u + w) * s - ox, (v + h) * s, z),
				Vector3(u * s - ox, (v + h) * s, z),
				Vector3(u * s - ox, v * s, z),
			]
		_:
			var z := slice * s - oz
			return [
				Vector3(u * s - ox, v * s, z),
				Vector3(u * s - ox, (v + h) * s, z),
				Vector3((u + w) * s - ox, (v + h) * s, z),
				Vector3((u + w) * s - ox, v * s, z),
			]

static func _emit_prisms(cells: Array, gx: int, gy: int, gz: int, s: float, ox: float, oz: float, faces: Array) -> void:
	for x in range(gx):
		for y in range(gy):
			for z in range(gz):
				var cell: Array = cells[x][y][z]
				if cell[0] != CellTypes.Type.PRISM:
					continue
				var o := Vector3(x * s - ox, y * s, z * s - oz)
				var orientation: int = cell[1]
				var color: int = cell[2]
				_emit_single_prism(o, s, orientation, color, faces)

static func _emit_single_prism(o: Vector3, s: float, orientation: int, color: int, faces: Array) -> void:
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

	faces.append([color, -axis_dir, [p_near[0], p_near[1], p_near[2]]])
	faces.append([color, axis_dir, [p_far[2], p_far[1], p_far[0]]])

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

		faces.append([color, side_normal, [a, b, c, d]])
