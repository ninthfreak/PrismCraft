class_name MeshExporter

# Why the last export was refused, or empty if it was written. A silently
# non-compliant export is the exact failure that produced the v1 situation: the
# spec was never enforced anywhere, so nothing ever reported it was violated.
static var last_export_errors: Array = []

# Greedy-mesh the model (or a box region of it) into a flat list of faces:
# [color_id, normal, quad_verts]. bmax = (-1,-1,-1) means the whole grid.
static func _collect_faces(cells: Array, gx: int, gy: int, gz: int, s: float, ox: float, oz: float, bmin := Vector3i.ZERO, bmax := Vector3i(-1, -1, -1)) -> Array:
	if bmax.x < 0:
		bmax = Vector3i(gx - 1, gy - 1, gz - 1)
	var faces: Array = []
	for dir in range(6):
		_greedy_mesh_dir(cells, gx, gy, gz, s, ox, oz, dir, faces, bmin, bmax)
	_emit_prisms(cells, gx, gy, gz, s, ox, oz, faces, bmin, bmax)
	# The greedy pass works one axis-aligned slice at a time, so it can never
	# merge a prism's hypotenuse. Those all lie in a handful of planes, and this
	# collapses each of them.
	return CoplanarMerge.merge(faces)

static func _in_box(x: int, y: int, z: int, bmin: Vector3i, bmax: Vector3i) -> bool:
	return x >= bmin.x and x <= bmax.x and y >= bmin.y and y <= bmax.y and z >= bmin.z and z <= bmax.z

# Binary glTF (.glb): one mesh, indexed, welded, baked vertex colors, single
# material — designed for one draw call at runtime. Returns triangle count.
static func export_glb(path: String, cells: Array, gx: int, gy: int, gz: int, cell_size: float, strict := true) -> int:
	var s := cell_size
	return _write_glb(path, _collect_faces(cells, gx, gy, gz, s, gx * s / 2.0, gz * s / 2.0), strict)

# Export only the voxels inside [bmin, bmax] as a .glb, keeping full-model world
# coordinates so exported parts reassemble in place. A region is a fragment of
# the model, so it is not expected to fill the unit cell — it is written
# unchecked.
static func export_glb_region(path: String, cells: Array, gx: int, gy: int, gz: int, cell_size: float, bmin: Vector3i, bmax: Vector3i) -> int:
	var s := cell_size
	return _write_glb(path, _collect_faces(cells, gx, gy, gz, s, gx * s / 2.0, gz * s / 2.0, bmin, bmax), false)

# strict: validate against the export contract and refuse to write on a
# violation, returning -1 with the reasons in last_export_errors. Pass false
# only to measure a pipeline that is known not to comply yet.
static func _write_glb(path: String, faces: Array, strict := true) -> int:
	if faces.is_empty():
		return 0

	var vmap := {}
	var positions := PackedFloat32Array()
	var normals := PackedFloat32Array()
	var indices := PackedInt32Array()
	var minp := Vector3(INF, INF, INF)
	var maxp := Vector3(-INF, -INF, -INF)
	var tri_count := 0

	for face in faces:
		var n: Vector3 = face[1]
		var quad: Array = face[2]

		# order verts so the front face (CCW) agrees with the normal
		var cross: Vector3 = (quad[1] - quad[0]).cross(quad[2] - quad[0])
		var ordered: Array = quad if cross.dot(n) > 0 else _reversed(quad)

		var idx: Array = []
		for vp in ordered:
			# Weld by position + normal only. Splitting on normal is what keeps
			# shading flat, and flat normals are load-bearing: the consumer picks
			# a texture projection plane from the normal, so a normal shared
			# across a face boundary would flip the projection mid-face and seam.
			var key := "%d_%d_%d_%d_%d_%d" % [
				int(round(vp.x * 1024.0)), int(round(vp.y * 1024.0)), int(round(vp.z * 1024.0)),
				int(round(n.x)), int(round(n.y)), int(round(n.z))]
			var vi: int
			if vmap.has(key):
				vi = vmap[key]
			else:
				vi = positions.size() / 3
				vmap[key] = vi
				positions.push_back(vp.x); positions.push_back(vp.y); positions.push_back(vp.z)
				normals.push_back(n.x); normals.push_back(n.y); normals.push_back(n.z)
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
	var idx_off := bin.size(); bin.append_array(idx_bytes)
	while bin.size() % 4 != 0:
		bin.push_back(0)

	# No material, no COLOR_0, no UVs: the consumer textures purely from world
	# position in-shader, and discards anything else the file carries.
	var gltf := {
		"asset": {"version": "2.0", "generator": "PrismCraft"},
		"scene": 0,
		"scenes": [{"nodes": [0]}],
		"nodes": [{"mesh": 0}],
		"meshes": [{"primitives": [{
			"attributes": {"POSITION": 0, "NORMAL": 1},
			"indices": 2, "mode": 4}]}],
		"buffers": [{"byteLength": bin.size()}],
		"bufferViews": [
			{"buffer": 0, "byteOffset": pos_off, "byteLength": pos_bytes.size(), "target": 34962},
			{"buffer": 0, "byteOffset": norm_off, "byteLength": norm_bytes.size(), "target": 34962},
			{"buffer": 0, "byteOffset": idx_off, "byteLength": idx_bytes.size(), "target": 34963}],
		"accessors": [
			{"bufferView": 0, "componentType": 5126, "count": nverts, "type": "VEC3",
				"min": [minp.x, minp.y, minp.z], "max": [maxp.x, maxp.y, maxp.z]},
			{"bufferView": 1, "componentType": 5126, "count": nverts, "type": "VEC3"},
			{"bufferView": 2, "componentType": 5125, "count": indices.size(), "type": "SCALAR"}]
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

	last_export_errors = []
	var report := GlbValidator.validate_bytes(out)
	if not report["ok"]:
		last_export_errors = report["errors"]
		if strict:
			for e in last_export_errors:
				printerr("[export] refused %s: %s" % [path.get_file(), e])
			return -1

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
					if ncell[0] == CellTypes.Type.PRISM and not CellTypes.is_cutout_cell(ncell):
						# A prism hides this face only where one of its legs covers
						# it outright. Against a cap or an open side the face stays,
						# because the prism leaves part of it exposed.
						var dn := _dir_normal(dir)
						var facing := Vector3i(int(round(-dn.x)), int(round(-dn.y)), int(round(-dn.z)))
						grid[u][v] = -1 if CellTypes.prism_covers_face(ncell[1], facing) else face_color
					elif ncell[0] != CellTypes.Type.SOLID or CellTypes.is_cutout_cell(ncell):
						# empty or cutout neighbor never fully occludes this face — a
						# cutout block has see-through holes, so faces behind and
						# beside it must survive.
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
				var axis: int = orientation / 4

				# Prisms merge along the axis only when they share orientation AND
				# all face colors, so per-face coloring survives export.
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
					if nc[0] != CellTypes.Type.PRISM or nc[1] != orientation or not CellTypes.same_face_colors(nc, cell):
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
					elif nc[0] == CellTypes.Type.SOLID and not CellTypes.is_cutout_cell(nc):
						near_capped = false  # buried against solid material
				var fnx: int = x; var fny: int = y; var fnz: int = z
				match axis:
					0: fny = y + run
					1: fnx = x + run
					_: fnz = z + run
				if fnx < gx and fny < gy and fnz < gz:
					var nc: Array = cells[fnx][fny][fnz]
					if nc[0] == CellTypes.Type.PRISM and nc[1] == orientation:
						far_capped = false
					elif nc[0] == CellTypes.Type.SOLID and not CellTypes.is_cutout_cell(nc):
						far_capped = false

				# Per-cell visibility of the two legs along the run. A leg buried
				# against solid material, or against another prism's leg, is
				# interior and must not be exported; the run can be partly buried,
				# so this is resolved cell by cell and emitted as maximal segments.
				var leg_vis := {}
				for ln in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0),
						Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
					if not CellTypes.prism_covers_face(orientation, ln):
						continue
					var vis: Array = []
					for r in range(run):
						var mx: int = x; var my: int = y; var mz: int = z
						match axis:
							0: my = y + r
							1: mx = x + r
							_: mz = z + r
						vis.append(_leg_visible(cells, gx, gy, gz, mx + ln.x, my + ln.y, mz + ln.z, ln, bmin, bmax))
					leg_vis[ln] = vis

				var o := Vector3(x * s - ox, y * s, z * s - oz)
				_emit_merged_prism(o, s, orientation, cell, run, near_capped, far_capped, faces, leg_vis)

# A prism leg is hidden when the cell it faces is opaque solid, or a prism whose
# own leg covers the shared face.
static func _leg_visible(cells: Array, gx: int, gy: int, gz: int, qx: int, qy: int, qz: int, n: Vector3i, bmin: Vector3i, bmax: Vector3i) -> bool:
	if qx < 0 or qx >= gx or qy < 0 or qy >= gy or qz < 0 or qz >= gz:
		return true
	if not _in_box(qx, qy, qz, bmin, bmax):
		return true
	var q: Array = cells[qx][qy][qz]
	if CellTypes.is_cutout_cell(q):
		return true
	if q[0] == CellTypes.Type.SOLID:
		return false
	if q[0] == CellTypes.Type.PRISM:
		return not CellTypes.prism_covers_face(q[1], -n)
	return true

# Face color id for a prism face normal, or -1 to skip (cutout hole).
static func _prism_face_id(cell: Array, normal: Vector3) -> int:
	var slot := CellTypes.slot_for_normal(normal)
	var cv: int = cell[slot]
	if CellTypes.is_rgb5551(cv) and CellTypes.decode_color(cv).a < CellTypes.ALPHA_THRESHOLD:
		return -1
	return cv

static func _emit_merged_prism(o: Vector3, s: float, orientation: int, cell: Array, run: int, near_cap: bool, far_cap: bool, faces: Array, leg_vis: Dictionary = {}) -> void:
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
		var nid := _prism_face_id(cell, -axis_dir)
		if nid >= 0:
			faces.append([nid, -axis_dir, [p_near[0], p_near[1], p_near[2]]])
	if far_cap:
		var fid := _prism_face_id(cell, axis_dir)
		if fid >= 0:
			faces.append([fid, axis_dir, [p_far[2], p_far[1], p_far[0]]])

	for i in range(3):
		var j := (i + 1) % 3
		var a := p_near[i]
		var b := p_near[j]

		var edge := (b - a).normalized()
		var side_normal := edge.cross(axis_dir).normalized()

		var third := p_near[(i + 2) % 3]
		if side_normal.dot(third - a) > 0:
			side_normal = -side_normal

		var sid := _prism_face_id(cell, side_normal)
		if sid < 0:
			continue

		# A leg has an axis-aligned normal and an entry in leg_vis; the
		# hypotenuse's normal is diagonal, faces no single cell, and so is never
		# occluded by a face neighbour.
		var key := Vector3i(int(round(side_normal.x)), int(round(side_normal.y)), int(round(side_normal.z)))
		if not leg_vis.has(key):
			faces.append([sid, side_normal, [a, b, p_far[j], p_far[i]]])
			continue

		var vis: Array = leg_vis[key]
		var r := 0
		while r < run:
			if not vis[r]:
				r += 1
				continue
			var r2 := r
			while r2 < run and vis[r2]:
				r2 += 1
			var near_off: Vector3 = axis_dir * (r * s)
			var far_off: Vector3 = axis_dir * (r2 * s)
			faces.append([sid, side_normal, [a + near_off, b + near_off, b + far_off, a + far_off]])
			r = r2
