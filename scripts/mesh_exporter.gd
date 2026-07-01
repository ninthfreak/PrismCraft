class_name MeshExporter

# Greedy-mesh the model (or a box region of it) into a flat list of faces:
# [color_id, normal, quad_verts]. bmax = (-1,-1,-1) means the whole grid.
static func _collect_faces(cells: Array, gx: int, gy: int, gz: int, s: float, ox: float, oz: float, bmin := Vector3i.ZERO, bmax := Vector3i(-1, -1, -1)) -> Array:
	if bmax.x < 0:
		bmax = Vector3i(gx - 1, gy - 1, gz - 1)
	var faces: Array = []
	for dir in range(6):
		_greedy_mesh_dir(cells, gx, gy, gz, s, ox, oz, dir, faces, bmin, bmax)
	_emit_prisms(cells, gx, gy, gz, s, ox, oz, faces, bmin, bmax)
	return faces

static func _in_box(x: int, y: int, z: int, bmin: Vector3i, bmax: Vector3i) -> bool:
	return x >= bmin.x and x <= bmax.x and y >= bmin.y and y <= bmax.y and z >= bmin.z and z <= bmax.z

static func export_obj(path: String, cells: Array, gx: int, gy: int, gz: int, cell_size: float) -> int:
	var s := cell_size
	var ox := gx * s / 2.0
	var oz := gz * s / 2.0
	var faces := _collect_faces(cells, gx, gy, gz, s, ox, oz)

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
			text += "usemtl " + CellTypes.color_name(cur_color) + "\n"
		var vi: int = fd[1]
		var ni: int = fd[3] + 1
		var n: Vector3 = norms[fd[3]]
		var cross: Vector3 = (verts[vi + 1] - verts[vi]).cross(verts[vi + 2] - verts[vi])
		var flip: bool = cross.dot(n) > 0
		vi += 1
		if fd[2] == 4:
			if flip:
				text += "f %d//%d %d//%d %d//%d %d//%d\n" % [vi, ni, vi + 1, ni, vi + 2, ni, vi + 3, ni]
			else:
				text += "f %d//%d %d//%d %d//%d %d//%d\n" % [vi + 3, ni, vi + 2, ni, vi + 1, ni, vi, ni]
		else:
			if flip:
				text += "f %d//%d %d//%d %d//%d\n" % [vi, ni, vi + 1, ni, vi + 2, ni]
			else:
				text += "f %d//%d %d//%d %d//%d\n" % [vi + 2, ni, vi + 1, ni, vi, ni]
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
		var c: Color = CellTypes.decode_color(ci)
		var cname: String = CellTypes.color_name(ci)
		mtl_text += "newmtl " + cname + "\n"
		mtl_text += "Kd %.4f %.4f %.4f\n" % [c.r, c.g, c.b]
		mtl_text += "Ka 0.1 0.1 0.1\n"
		if c.a < 1.0:
			mtl_text += "d %.4f\n\n" % c.a
		else:
			mtl_text += "d 1.0\n\n"

	var mtl_path := path.get_base_dir().path_join(mtl_file)
	var mfile := FileAccess.open(mtl_path, FileAccess.WRITE)
	if mfile:
		mfile.store_string(mtl_text)
		mfile.close()

	return face_count

# Binary glTF (.glb): one mesh, indexed, welded, baked vertex colors, single
# material — designed for one draw call at runtime. Returns triangle count.
static func export_glb(path: String, cells: Array, gx: int, gy: int, gz: int, cell_size: float) -> int:
	var s := cell_size
	return _write_glb(path, _collect_faces(cells, gx, gy, gz, s, gx * s / 2.0, gz * s / 2.0))

# Export only the voxels inside [bmin, bmax] as a .glb, keeping full-model world
# coordinates so exported parts reassemble in place. Used for segmented rigs.
static func export_glb_region(path: String, cells: Array, gx: int, gy: int, gz: int, cell_size: float, bmin: Vector3i, bmax: Vector3i) -> int:
	var s := cell_size
	return _write_glb(path, _collect_faces(cells, gx, gy, gz, s, gx * s / 2.0, gz * s / 2.0, bmin, bmax))

static func _write_glb(path: String, faces: Array) -> int:
	if faces.is_empty():
		return 0

	var vmap := {}
	var positions := PackedFloat32Array()
	var normals := PackedFloat32Array()
	var colors := PackedByteArray()
	var indices := PackedInt32Array()
	var minp := Vector3(INF, INF, INF)
	var maxp := Vector3(-INF, -INF, -INF)
	var tri_count := 0

	for face in faces:
		var color_id: int = face[0]
		var n: Vector3 = face[1]
		var quad: Array = face[2]
		var col := CellTypes.decode_color(color_id)
		var cr := clampi(int(round(col.r * 255.0)), 0, 255)
		var cg := clampi(int(round(col.g * 255.0)), 0, 255)
		var cb := clampi(int(round(col.b * 255.0)), 0, 255)
		var ca := clampi(int(round(col.a * 255.0)), 0, 255)

		# order verts so the front face (CCW) agrees with the normal
		var cross: Vector3 = (quad[1] - quad[0]).cross(quad[2] - quad[0])
		var ordered: Array = quad if cross.dot(n) > 0 else _reversed(quad)

		var idx: Array = []
		for vp in ordered:
			# weld by position + normal + color to preserve flat shading
			var key := "%d_%d_%d_%d_%d_%d_%d" % [
				int(round(vp.x * 1024.0)), int(round(vp.y * 1024.0)), int(round(vp.z * 1024.0)),
				int(round(n.x)), int(round(n.y)), int(round(n.z)), color_id]
			var vi: int
			if vmap.has(key):
				vi = vmap[key]
			else:
				vi = positions.size() / 3
				vmap[key] = vi
				positions.push_back(vp.x); positions.push_back(vp.y); positions.push_back(vp.z)
				normals.push_back(n.x); normals.push_back(n.y); normals.push_back(n.z)
				colors.push_back(cr); colors.push_back(cg); colors.push_back(cb); colors.push_back(ca)
				minp.x = minf(minp.x, vp.x); minp.y = minf(minp.y, vp.y); minp.z = minf(minp.z, vp.z)
				maxp.x = maxf(maxp.x, vp.x); maxp.y = maxf(maxp.y, vp.y); maxp.z = maxf(maxp.z, vp.z)
			idx.append(vi)
		for t in range(1, idx.size() - 1):
			indices.push_back(idx[0]); indices.push_back(idx[t]); indices.push_back(idx[t + 1])
			tri_count += 1

	var nverts := positions.size() / 3
	var pos_bytes := positions.to_byte_array()
	var norm_bytes := normals.to_byte_array()
	var idx_bytes := indices.to_byte_array()

	var bin := PackedByteArray()
	var pos_off := bin.size(); bin.append_array(pos_bytes)
	var norm_off := bin.size(); bin.append_array(norm_bytes)
	var col_off := bin.size(); bin.append_array(colors)
	var idx_off := bin.size(); bin.append_array(idx_bytes)
	while bin.size() % 4 != 0:
		bin.push_back(0)

	var gltf := {
		"asset": {"version": "2.0", "generator": "PrismCraft"},
		"scene": 0,
		"scenes": [{"nodes": [0]}],
		"nodes": [{"mesh": 0}],
		"meshes": [{"primitives": [{
			"attributes": {"POSITION": 0, "NORMAL": 1, "COLOR_0": 2},
			"indices": 3, "material": 0, "mode": 4}]}],
		"materials": [{
			"name": "voxel",
			"pbrMetallicRoughness": {"baseColorFactor": [1, 1, 1, 1], "metallicFactor": 0.0, "roughnessFactor": 1.0},
			"doubleSided": false}],
		"buffers": [{"byteLength": bin.size()}],
		"bufferViews": [
			{"buffer": 0, "byteOffset": pos_off, "byteLength": pos_bytes.size(), "target": 34962},
			{"buffer": 0, "byteOffset": norm_off, "byteLength": norm_bytes.size(), "target": 34962},
			{"buffer": 0, "byteOffset": col_off, "byteLength": colors.size(), "target": 34962},
			{"buffer": 0, "byteOffset": idx_off, "byteLength": idx_bytes.size(), "target": 34963}],
		"accessors": [
			{"bufferView": 0, "componentType": 5126, "count": nverts, "type": "VEC3",
				"min": [minp.x, minp.y, minp.z], "max": [maxp.x, maxp.y, maxp.z]},
			{"bufferView": 1, "componentType": 5126, "count": nverts, "type": "VEC3"},
			{"bufferView": 2, "componentType": 5121, "normalized": true, "count": nverts, "type": "VEC4"},
			{"bufferView": 3, "componentType": 5125, "count": indices.size(), "type": "SCALAR"}]
	}

	var json_bytes := JSON.stringify(gltf).to_utf8_buffer()
	while json_bytes.size() % 4 != 0:
		json_bytes.push_back(0x20)

	var total := 12 + 8 + json_bytes.size() + 8 + bin.size()
	var out := PackedByteArray()
	out.append_array(_u32(0x46546C67))   # "glTF"
	out.append_array(_u32(2))
	out.append_array(_u32(total))
	out.append_array(_u32(json_bytes.size()))
	out.append_array(_u32(0x4E4F534A))   # "JSON"
	out.append_array(json_bytes)
	out.append_array(_u32(bin.size()))
	out.append_array(_u32(0x004E4942))   # "BIN\0"
	out.append_array(bin)

	var file := FileAccess.open(path, FileAccess.WRITE)
	if not file:
		return 0
	file.store_buffer(out)
	file.close()
	return tri_count

static func _reversed(arr: Array) -> Array:
	var r := arr.duplicate()
	r.reverse()
	return r

static func _u32(v: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(4)
	b.encode_u32(0, v)
	return b

static func _greedy_mesh_dir(cells: Array, gx: int, gy: int, gz: int, s: float, ox: float, oz: float, dir: int, faces: Array, bmin: Vector3i, bmax: Vector3i) -> void:
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

				var src_cell: Array = cells[cx][cy][cz]
				if src_cell[0] != CellTypes.Type.SOLID or not _in_box(cx, cy, cz, bmin, bmax):
					grid[u][v] = -1
					continue

				var face_idx: int = dir + 2
				var face_color: int = src_cell[face_idx]
				if CellTypes.is_rgb5551(face_color) and CellTypes.decode_color(face_color).a < CellTypes.ALPHA_THRESHOLD:
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

				if nx < 0 or nx >= gx or ny < 0 or ny >= gy or nz < 0 or nz >= gz or not _in_box(nx, ny, nz, bmin, bmax):
					grid[u][v] = face_color
				else:
					var ncell: Array = cells[nx][ny][nz]
					if ncell[0] != CellTypes.Type.SOLID:
						# empty or prism neighbor never fully occludes this face
						grid[u][v] = face_color
					else:
						# A face between two solid cells is hidden when the neighbor's
						# facing side is opaque (RGB5551 alpha is 1-bit). Only a genuine
						# alpha-0 hole leaves it visible. Matches block_mesh_builder and
						# avoids exporting the model's hidden interior geometry.
						var opp: int = ncell[(dir ^ 1) + 2]
						if CellTypes.is_rgb5551(opp) and CellTypes.decode_color(opp).a < CellTypes.ALPHA_THRESHOLD:
							grid[u][v] = face_color
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

static func _rgb565_near(a: int, b: int) -> bool:
	if a == b:
		return true
	var ar := (a >> 11) & 0x1F; var ag := (a >> 5) & 0x3F; var ab := a & 0x1F
	var br := (b >> 11) & 0x1F; var bg := (b >> 5) & 0x3F; var bb := b & 0x1F
	return absi(ar - br) <= 1 and absi(ag - bg) <= 2 and absi(ab - bb) <= 1

static func _emit_prisms(cells: Array, gx: int, gy: int, gz: int, s: float, ox: float, oz: float, faces: Array, bmin: Vector3i, bmax: Vector3i) -> void:
	var visited := {}
	for x in range(gx):
		for y in range(gy):
			for z in range(gz):
				var cell: Array = cells[x][y][z]
				if cell[0] != CellTypes.Type.PRISM:
					continue
				if not _in_box(x, y, z, bmin, bmax):
					continue
				var key := x + y * gx + z * gx * gy
				if visited.has(key):
					continue
				var orientation: int = cell[1]
				var color: int = cell[2]
				var axis: int = orientation / 4

				var run := 1
				while true:
					var nx: int = x; var ny: int = y; var nz: int = z
					match axis:
						0: ny = y + run
						1: nx = x + run
						_: nz = z + run
					if nx >= gx or ny >= gy or nz >= gz:
						break
					var nc: Array = cells[nx][ny][nz]
					if nc[0] != CellTypes.Type.PRISM or nc[1] != orientation or not _rgb565_near(nc[2], color):
						break
					run += 1

				for r in range(run):
					var mx: int = x; var my: int = y; var mz: int = z
					match axis:
						0: my = y + r
						1: mx = x + r
						_: mz = z + r
					visited[mx + my * gx + mz * gx * gy] = true

				var near_capped := true
				var far_capped := true
				var nnx: int = x; var nny: int = y; var nnz: int = z
				match axis:
					0: nny = y - 1
					1: nnx = x - 1
					_: nnz = z - 1
				if nnx >= 0 and nny >= 0 and nnz >= 0:
					var nc: Array = cells[nnx][nny][nnz]
					if nc[0] == CellTypes.Type.PRISM and nc[1] == orientation:
						near_capped = false
				var fnx: int = x; var fny: int = y; var fnz: int = z
				match axis:
					0: fny = y + run
					1: fnx = x + run
					_: fnz = z + run
				if fnx < gx and fny < gy and fnz < gz:
					var nc: Array = cells[fnx][fny][fnz]
					if nc[0] == CellTypes.Type.PRISM and nc[1] == orientation:
						far_capped = false

				var o := Vector3(x * s - ox, y * s, z * s - oz)
				_emit_merged_prism(o, s, orientation, color, run, near_capped, far_capped, faces)

static func _emit_merged_prism(o: Vector3, s: float, orientation: int, color: int, run: int, near_cap: bool, far_cap: bool, faces: Array) -> void:
	var axis: int = orientation / 4
	var corner: int = orientation % 4

	var tri_2d: Array[Vector2]
	match corner:
		0: tri_2d = [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1)]
		1: tri_2d = [Vector2(1, 0), Vector2(1, 1), Vector2(0, 0)]
		2: tri_2d = [Vector2(1, 1), Vector2(0, 1), Vector2(1, 0)]
		_: tri_2d = [Vector2(0, 1), Vector2(0, 0), Vector2(1, 1)]

	var run_s := run * s
	var p_near: Array[Vector3] = []
	var p_far: Array[Vector3] = []

	for uv in tri_2d:
		var near: Vector3
		var far: Vector3
		match axis:
			0:
				near = o + Vector3(uv.x * s, 0, uv.y * s)
				far = o + Vector3(uv.x * s, run_s, uv.y * s)
			1:
				near = o + Vector3(0, uv.x * s, uv.y * s)
				far = o + Vector3(run_s, uv.x * s, uv.y * s)
			_:
				near = o + Vector3(uv.x * s, uv.y * s, 0)
				far = o + Vector3(uv.x * s, uv.y * s, run_s)
		p_near.append(near)
		p_far.append(far)

	var axis_dir: Vector3
	match axis:
		0: axis_dir = Vector3.UP
		1: axis_dir = Vector3.RIGHT
		_: axis_dir = Vector3.BACK

	if near_cap:
		faces.append([color, -axis_dir, [p_near[0], p_near[1], p_near[2]]])
	if far_cap:
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
