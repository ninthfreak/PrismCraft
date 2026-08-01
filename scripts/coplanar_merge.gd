class_name CoplanarMerge

# Merges coplanar quads into maximal rectangles.
#
# Why this exists: the greedy mesher works per axis-aligned slice, so it can
# never merge a face that is not axis-aligned. _emit_prisms() emits every prism
# cell's hypotenuse separately, which leaves a 32-cell ramp slope at ~32 quads
# no matter what colour it is. Every one of those quads lies in a single plane,
# so a pass that groups by plane and merges within it collapses the whole slope
# to one quad.
#
# The merge is deliberately restricted to rectangles that share a full edge,
# rather than a general polygon union. Every face this exporter produces comes
# off a voxel lattice, so within a plane the quads are rectangles on a regular
# grid and full-edge merging reaches the same answer a boolean union would for
# the shapes we actually build. In exchange it cannot produce holes, slivers or
# zero-area output — the failure modes that would be invisible in a viewport and
# that nobody can currently eyeball. Anything it does not understand (triangles,
# non-rectangles, mismatched planes) is passed through untouched, so the pass is
# never destructive; the worst case is that it merges nothing.
#
# Face format matches MeshExporter: [normal: Vector3, verts: Array].

# Lattice for comparing positions within a plane. Coordinates are multiples of
# the cell size (1/32, exact in binary) or that times sqrt(2) for 45deg planes,
# so this only has to absorb ULP noise, not real spacing.
const QUANT := 1e-4
const PLANE_QUANT := 1e-4


static func merge(faces: Array) -> Array:
	if faces.size() < 2:
		return faces.duplicate()

	# Group by plane. Normals are NOT sign-canonicalised: two faces on the same
	# plane pointing opposite ways are back-to-back surfaces and must stay
	# separate.
	var groups := {}
	var order: Array = []
	for face in faces:
		var key := _plane_key(face)
		if not groups.has(key):
			groups[key] = []
			order.append(key)
		groups[key].append(face)

	var out: Array = []
	for key in order:
		var group: Array = groups[key]
		if group.size() < 2:
			out.append_array(group)
		else:
			out.append_array(_merge_group(group))
	return out


static func _plane_key(face: Array) -> String:
	var n: Vector3 = (face[0] as Vector3).normalized()
	var verts: Array = face[1]
	var d: float = n.dot(verts[0])
	return "%d|%d|%d|%d" % [
		int(round(n.x / PLANE_QUANT)),
		int(round(n.y / PLANE_QUANT)),
		int(round(n.z / PLANE_QUANT)),
		int(round(d / PLANE_QUANT)),
	]


static func _merge_group(group: Array) -> Array:
	var n: Vector3 = (group[0][0] as Vector3).normalized()

	# Basis taken from the first quad's own edge, so the rectangles in this plane
	# are axis-aligned in it. u x w = n, so (u, w) is right-handed seen from +n
	# and CCW order in 2D reconstructs a correctly wound quad.
	var first: Array = group[0][1]
	if first.size() != 4:
		return group
	var u: Vector3 = (first[1] - first[0])
	if u.length() < 1e-12:
		return group
	u = u.normalized()
	var w: Vector3 = n.cross(u).normalized()
	if w.length() < 0.5:
		return group
	var origin: Vector3 = first[0]

	# Project every quad and demand it be an axis-aligned rectangle in this
	# basis. One face that is not means this group is something the pass does not
	# model, so leave the whole group alone rather than guess.
	var rects: Array = []
	var xvals := {}
	var yvals := {}
	for face in group:
		var verts: Array = face[1]
		if verts.size() != 4:
			return group
		var qx: Array = []
		var qy: Array = []
		for v in verts:
			var rel: Vector3 = v - origin
			var px: float = rel.dot(u)
			var py: float = rel.dot(w)
			var ix := int(round(px / QUANT))
			var iy := int(round(py / QUANT))
			xvals[ix] = px
			yvals[iy] = py
			qx.append(ix)
			qy.append(iy)

		var x0: int = qx.min()
		var x1: int = qx.max()
		var y0: int = qy.min()
		var y1: int = qy.max()
		if x0 == x1 or y0 == y1:
			return group  # degenerate in-plane; not ours to touch
		# every corner must sit on one of the two x and one of the two y lines
		for i in range(4):
			if (qx[i] != x0 and qx[i] != x1) or (qy[i] != y0 and qy[i] != y1):
				return group
		rects.append([x0, x1, y0, y1])

	var merged := _merge_rects(rects)
	if merged.size() >= rects.size():
		return group  # nothing gained; keep the originals verbatim

	var out: Array = []
	for r in merged:
		var ax: float = xvals[r[0]]
		var bx: float = xvals[r[1]]
		var ay: float = yvals[r[2]]
		var by: float = yvals[r[3]]
		out.append([n, [
			origin + u * ax + w * ay,
			origin + u * bx + w * ay,
			origin + u * bx + w * by,
			origin + u * ax + w * by,
		]])
	return out


# Repeatedly fuse any two rectangles that share a full edge, until a pass makes
# no progress. A strip of 32 collapses to 1; a full rectangular tiling collapses
# to 1; an L stays as 2 (no hole is ever created).
static func _merge_rects(rects: Array) -> Array:
	var work: Array = rects.duplicate(true)
	var changed := true
	while changed:
		changed = false
		var i := 0
		while i < work.size():
			var j := i + 1
			while j < work.size():
				var m = _try_fuse(work[i], work[j])
				if m == null:
					j += 1
				else:
					work[i] = m
					work.remove_at(j)
					changed = true
			i += 1
	return work


static func _try_fuse(a: Array, b: Array):
	# same y-span, touching in x
	if a[2] == b[2] and a[3] == b[3]:
		if a[1] == b[0]:
			return [a[0], b[1], a[2], a[3]]
		if b[1] == a[0]:
			return [b[0], a[1], a[2], a[3]]
	# same x-span, touching in y
	if a[0] == b[0] and a[1] == b[1]:
		if a[3] == b[2]:
			return [a[0], a[1], a[2], b[3]]
		if b[3] == a[2]:
			return [a[0], a[1], b[2], a[3]]
	return null
