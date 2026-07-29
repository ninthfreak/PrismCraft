class_name GlbValidator

# Validates an exported .glb against the PrismCraft v2 shape-export contract.
#
# Everything here is static and side-effect free so the same code can run in two
# places: tools/validate_shapes.gd checks files already on disk, and the
# exporter checks the byte buffer it is about to write and refuses to write a
# non-compliant one. A shape that fails must never reach the consumer silently —
# an unenforced spec is what produced the v1 situation.

const MAX_TRIS := 500
const BOUND_TOL := 0.001

# A legitimate face is at minimum a prism cap: two legs of one cell (1/32),
# area 1/2048, so |cross| ~= 1e-3. A truly collapsed triangle does not reach
# zero either, because Vector3 is single-precision: its cross lands around
# 3e-8 (unit-cell coordinates times float epsilon). This sits in the gap
# between those two, orders of magnitude clear of both.
const AREA_EPS := 1e-6
const NORMAL_TOL := 1e-3

const _GLB_MAGIC := 0x46546C67   # "glTF"
const _CHUNK_JSON := 0x4E4F534A  # "JSON"
const _CHUNK_BIN := 0x004E4942   # "BIN\0"

const _CT_BYTE := 5120
const _CT_UBYTE := 5121
const _CT_SHORT := 5122
const _CT_USHORT := 5123
const _CT_UINT := 5125
const _CT_FLOAT := 5126


# Returns {"ok": bool, "errors": Array[String], "stats": Dictionary}.
# Errors are cumulative where it is safe to continue, so one run reports every
# rule a file breaks rather than only the first.
static func validate_bytes(data: PackedByteArray) -> Dictionary:
	var errors: Array = []
	var stats := {"triangles": 0, "vertices": 0, "bounds_min": Vector3.ZERO, "bounds_max": Vector3.ZERO}

	var parsed := _parse_glb(data)
	if parsed.has("error"):
		return {"ok": false, "errors": [parsed["error"]], "stats": stats}

	var gltf: Dictionary = parsed["json"]
	var bin: PackedByteArray = parsed["bin"]

	# ── structure ────────────────────────────────────────────────────────────
	var meshes: Array = gltf.get("meshes", [])
	var nodes: Array = gltf.get("nodes", [])

	if meshes.size() != 1:
		errors.append("expected exactly 1 mesh, found %d" % meshes.size())
	if nodes.size() != 1:
		errors.append("expected exactly 1 node, found %d" % nodes.size())

	if gltf.has("materials") and (gltf["materials"] as Array).size() > 0:
		errors.append("materials present (%d) — the contract forbids materials" % (gltf["materials"] as Array).size())
	if gltf.has("images") and (gltf["images"] as Array).size() > 0:
		errors.append("images present (%d) — the contract forbids embedded images" % (gltf["images"] as Array).size())
	if gltf.has("textures") and (gltf["textures"] as Array).size() > 0:
		errors.append("textures present (%d)" % (gltf["textures"] as Array).size())
	if gltf.has("skins") and (gltf["skins"] as Array).size() > 0:
		errors.append("skins present (%d)" % (gltf["skins"] as Array).size())
	if gltf.has("animations") and (gltf["animations"] as Array).size() > 0:
		errors.append("animations present (%d)" % (gltf["animations"] as Array).size())

	if nodes.size() > 0:
		var node: Dictionary = nodes[0]
		for key in ["matrix", "translation", "rotation", "scale"]:
			if node.has(key):
				errors.append("node carries a '%s' transform — the node must be identity" % key)
		if node.has("skin"):
			errors.append("node is skinned")

	if meshes.is_empty():
		return {"ok": false, "errors": errors, "stats": stats}

	var prims: Array = (meshes[0] as Dictionary).get("primitives", [])
	if prims.size() != 1:
		errors.append("expected exactly 1 primitive, found %d" % prims.size())
	if prims.is_empty():
		return {"ok": false, "errors": errors, "stats": stats}

	var prim: Dictionary = prims[0]
	var attrs: Dictionary = prim.get("attributes", {})

	if prim.get("mode", 4) != 4:
		errors.append("primitive mode %d — must be 4 (TRIANGLES)" % prim.get("mode", 4))
	if prim.has("material"):
		errors.append("primitive references a material")
	if not prim.has("indices"):
		errors.append("primitive is not indexed")

	if not attrs.has("POSITION"):
		errors.append("POSITION attribute missing")
	if not attrs.has("NORMAL"):
		errors.append("NORMAL attribute missing")

	for attr_name in attrs.keys():
		var an := str(attr_name)
		if an.begins_with("TEXCOORD"):
			errors.append("UV attribute '%s' present — the consumer derives UVs in-shader" % an)
		elif an.begins_with("COLOR"):
			errors.append("vertex-color attribute '%s' present" % an)
		elif an.begins_with("JOINTS") or an.begins_with("WEIGHTS"):
			errors.append("skinning attribute '%s' present" % an)

	if not attrs.has("POSITION") or not prim.has("indices"):
		return {"ok": errors.is_empty(), "errors": errors, "stats": stats}

	# ── geometry ─────────────────────────────────────────────────────────────
	var accessors: Array = gltf.get("accessors", [])
	var views: Array = gltf.get("bufferViews", [])

	var pos := _read_vec3(accessors, views, bin, int(attrs["POSITION"]))
	var nrm: PackedVector3Array = PackedVector3Array()
	if attrs.has("NORMAL"):
		nrm = _read_vec3(accessors, views, bin, int(attrs["NORMAL"]))
	var idx := _read_scalar(accessors, views, bin, int(prim["indices"]))

	stats["vertices"] = pos.size()

	if pos.is_empty():
		errors.append("mesh has no vertices")
		return {"ok": false, "errors": errors, "stats": stats}
	if not nrm.is_empty() and nrm.size() != pos.size():
		errors.append("NORMAL count (%d) != POSITION count (%d)" % [nrm.size(), pos.size()])
	if idx.size() % 3 != 0:
		errors.append("index count %d is not a multiple of 3" % idx.size())

	var tri_count := idx.size() / 3
	stats["triangles"] = tri_count
	if tri_count > MAX_TRIS:
		errors.append("triangle count %d exceeds the budget of %d" % [tri_count, MAX_TRIS])

	# bounds
	var mn := Vector3(INF, INF, INF)
	var mx := Vector3(-INF, -INF, -INF)
	for p in pos:
		mn.x = minf(mn.x, p.x); mn.y = minf(mn.y, p.y); mn.z = minf(mn.z, p.z)
		mx.x = maxf(mx.x, p.x); mx.y = maxf(mx.y, p.y); mx.z = maxf(mx.z, p.z)
	stats["bounds_min"] = mn
	stats["bounds_max"] = mx

	if mn.x < -0.5 - BOUND_TOL or mx.x > 0.5 + BOUND_TOL:
		errors.append("x out of unit cell: [%.5f, %.5f], allowed [-0.5, 0.5]" % [mn.x, mx.x])
	if mn.z < -0.5 - BOUND_TOL or mx.z > 0.5 + BOUND_TOL:
		errors.append("z out of unit cell: [%.5f, %.5f], allowed [-0.5, 0.5]" % [mn.z, mx.z])
	if mn.y < -BOUND_TOL or mx.y > 1.0 + BOUND_TOL:
		errors.append("y out of unit cell: [%.5f, %.5f], allowed [0, 1]" % [mn.y, mx.y])

	# per-triangle checks
	var degenerate := 0
	var smooth_shaded := 0
	var wound_wrong := 0
	var bad_index := false

	for t in range(tri_count):
		var i0: int = idx[t * 3]
		var i1: int = idx[t * 3 + 1]
		var i2: int = idx[t * 3 + 2]
		if i0 >= pos.size() or i1 >= pos.size() or i2 >= pos.size():
			bad_index = true
			continue
		if i0 == i1 or i1 == i2 or i0 == i2:
			degenerate += 1
			continue

		var a: Vector3 = pos[i0]
		var b: Vector3 = pos[i1]
		var c: Vector3 = pos[i2]
		var cross := (b - a).cross(c - a)
		if cross.length() < AREA_EPS:
			degenerate += 1
			continue

		if nrm.size() == pos.size():
			var n0: Vector3 = nrm[i0]
			var n1: Vector3 = nrm[i1]
			var n2: Vector3 = nrm[i2]
			# Flat shading is a hard requirement, not a preference: the consumer
			# picks a texture projection plane from the normal, so a normal that
			# varies across a face flips the projection mid-face and seams.
			if n0.distance_to(n1) > NORMAL_TOL or n0.distance_to(n2) > NORMAL_TOL:
				smooth_shaded += 1
			elif cross.normalized().dot(n0.normalized()) < 0.0:
				wound_wrong += 1

	if bad_index:
		errors.append("index buffer references vertices outside the POSITION accessor")
	if degenerate > 0:
		errors.append("%d degenerate (zero-area) triangle(s)" % degenerate)
	if smooth_shaded > 0:
		errors.append("%d triangle(s) have per-vertex (smoothed) normals — normals must be flat per face" % smooth_shaded)
	if wound_wrong > 0:
		errors.append("%d triangle(s) wound against their normal" % wound_wrong)

	return {"ok": errors.is_empty(), "errors": errors, "stats": stats}


static func validate_file(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {"ok": false, "errors": ["cannot open %s" % path], "stats": {}}
	var data := f.get_buffer(f.get_length())
	f.close()
	return validate_bytes(data)


# ── GLB container ────────────────────────────────────────────────────────────
static func _parse_glb(data: PackedByteArray) -> Dictionary:
	if data.size() < 12:
		return {"error": "file is %d bytes — too short to be a GLB" % data.size()}
	if data.decode_u32(0) != _GLB_MAGIC:
		return {"error": "bad GLB magic — not a binary glTF"}
	var version := data.decode_u32(4)
	if version != 2:
		return {"error": "glTF version %d — expected 2" % version}
	var total := data.decode_u32(8)
	if total != data.size():
		return {"error": "header length %d != actual size %d" % [total, data.size()]}

	var json_dict := {}
	var bin := PackedByteArray()
	var got_json := false
	var off := 12
	while off + 8 <= data.size():
		var clen := data.decode_u32(off)
		var ctype := data.decode_u32(off + 4)
		var cstart := off + 8
		if cstart + clen > data.size():
			return {"error": "chunk at offset %d overruns the file" % off}
		if ctype == _CHUNK_JSON:
			var txt := data.slice(cstart, cstart + clen).get_string_from_utf8()
			var parsed = JSON.parse_string(txt)
			if typeof(parsed) != TYPE_DICTIONARY:
				return {"error": "JSON chunk does not parse to an object"}
			json_dict = parsed
			got_json = true
		elif ctype == _CHUNK_BIN:
			bin = data.slice(cstart, cstart + clen)
		off = cstart + clen
		# chunks are 4-byte aligned
		while off % 4 != 0:
			off += 1

	if not got_json:
		return {"error": "no JSON chunk found"}
	return {"json": json_dict, "bin": bin}


static func _component_size(ct: int) -> int:
	match ct:
		_CT_BYTE, _CT_UBYTE: return 1
		_CT_SHORT, _CT_USHORT: return 2
		_CT_UINT, _CT_FLOAT: return 4
	return 0


static func _view_offset(accessors: Array, views: Array, ai: int) -> Dictionary:
	if ai < 0 or ai >= accessors.size():
		return {}
	var acc: Dictionary = accessors[ai]
	if not acc.has("bufferView"):
		return {}
	var vi := int(acc["bufferView"])
	if vi < 0 or vi >= views.size():
		return {}
	var view: Dictionary = views[vi]
	var base := int(view.get("byteOffset", 0)) + int(acc.get("byteOffset", 0))
	return {"offset": base, "count": int(acc.get("count", 0)),
		"ct": int(acc.get("componentType", 0)), "stride": int(view.get("byteStride", 0))}


static func _read_vec3(accessors: Array, views: Array, bin: PackedByteArray, ai: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	var info := _view_offset(accessors, views, ai)
	if info.is_empty() or info["ct"] != _CT_FLOAT:
		return out
	var stride: int = info["stride"] if info["stride"] > 0 else 12
	for i in range(info["count"]):
		var o: int = info["offset"] + i * stride
		if o + 12 > bin.size():
			break
		out.append(Vector3(bin.decode_float(o), bin.decode_float(o + 4), bin.decode_float(o + 8)))
	return out


static func _read_scalar(accessors: Array, views: Array, bin: PackedByteArray, ai: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	var info := _view_offset(accessors, views, ai)
	if info.is_empty():
		return out
	var csz := _component_size(info["ct"])
	if csz == 0:
		return out
	var stride: int = info["stride"] if info["stride"] > 0 else csz
	for i in range(info["count"]):
		var o: int = info["offset"] + i * stride
		if o + csz > bin.size():
			break
		match info["ct"]:
			_CT_UINT: out.append(bin.decode_u32(o))
			_CT_USHORT: out.append(bin.decode_u16(o))
			_CT_UBYTE: out.append(bin.decode_u8(o))
			_: return PackedInt32Array()
	return out
