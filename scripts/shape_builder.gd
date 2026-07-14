class_name ShapeBuilder
# Builds predefined prism shapes (ramp, gable, diagonal wall, diamond, chamfered
# cube, cross) from an exact-size 1:1 atlas into a cell grid.
#
# Each shape is constructed in a fixed CANONICAL orientation, then rotated about
# Y and/or flipped vertically to reach the orientation the user picked in the
# import preview. The two transforms remap cell position, prism orientation, and
# per-face colors together. Remap tables were derived from the prism geometry in
# block_mesh_builder (see scratchpad/derive_remaps.py) and verified rot^4 == id.
#
# Prism orientation = axis*4 + corner, axis 0=Y 1=X 2=Z, corner 0=SW 1=SE 2=NE 3=NW.

const CHAMFER_COLUMN := 4
const CROSS_ARM := 16
const CROSS_DEPTH := 8
const DIAGWALL_T := 8

# Y-rotation 90 CCW: source(x,z) -> dest(z, N-1-x). Faces: +X->-Z, +Z->+X, etc.
const ROT_ORIENT := [3, 0, 1, 2, 8, 11, 10, 9, 7, 4, 5, 6]
# face index (2..7) remap under one CCW turn
const ROT_FACE := {2: 2, 3: 3, 4: 7, 5: 6, 6: 4, 7: 5}
# Vertical flip (y -> N-1-y): top<->bottom, prism corners mirror.
const FLIP_ORIENT := [0, 1, 2, 3, 5, 4, 7, 6, 11, 10, 9, 8]
const FLIP_FACE := {2: 3, 3: 2, 4: 4, 5: 5, 6: 6, 7: 7}
# X-rotation 90: grid dest(x, z, gy-1-y). Faces: +Y->-Z, +Z->+Y, X unchanged.
const ROTX_ORIENT := [8, 9, 10, 11, 7, 4, 5, 6, 3, 2, 1, 0]
const ROTX_FACE := {2: 7, 3: 6, 4: 4, 5: 5, 6: 2, 7: 3}

# ─────────────────────────────────────────────────────────────────────────────
# Public entry. opt = {"facing": int 0..3, "inverted": bool} (shape-dependent).
static func build(shape: String, img: Image, use_alpha: bool, gx: int, gy: int, gz: int, opt: Dictionary = {}) -> Array:
	var cells: Array
	match shape:
		"ramp": cells = _build_ramp(img, use_alpha, gx, gy, gz)
		"gable": cells = _build_gable(img, use_alpha, gx, gy, gz)
		"diagwall": cells = _build_diagwall(img, use_alpha, gx, gy, gz)
		"diamond": cells = _build_chamfered_box(img, gx / 2, use_alpha, gx, gy, gz)
		"chamfered": cells = _build_chamfered_box(img, CHAMFER_COLUMN, use_alpha, gx, gy, gz)
		"cross": cells = _build_cross(img, use_alpha, gx, gy, gz)
		"panel": cells = _build_slab(img, 1, use_alpha, gx, gy, gz)
		"slab_quarter": cells = _build_slab(img, 8, use_alpha, gx, gy, gz)
		"slab_half": cells = _build_slab(img, 16, use_alpha, gx, gy, gz)
		"stairs_4": cells = _build_stairs(img, 4, use_alpha, gx, gy, gz)
		"pipe_quarter": cells = _build_pipe_quarter(img, use_alpha, gx, gy, gz)
		_: return _new_cells(gx, gy, gz)

	var facing: int = opt.get("facing", 0)
	for i in range(facing % 4):
		cells = rotate_y(cells, gx, gy, gz)
	if opt.get("inverted", false):
		cells = flip_vertical(cells, gx, gy, gz)
	# Extra explicit transform ops (rx / ry / flip), applied in order.
	for op in opt.get("ops", []):
		match op:
			"rx": cells = rotate_x(cells, gx, gy, gz)
			"ry": cells = rotate_y(cells, gx, gy, gz)
			"flip": cells = flip_vertical(cells, gx, gy, gz)
	return cells

# ─── grid helpers ────────────────────────────────────────────────────────────
static func _new_cells(gx: int, gy: int, gz: int) -> Array:
	var cells: Array = []
	cells.resize(gx)
	for x in range(gx):
		var col: Array = []
		col.resize(gy)
		for y in range(gy):
			var row: Array = []
			row.resize(gz)
			for z in range(gz):
				row[z] = CellTypes.empty_cell()
			col[y] = row
		cells[x] = col
	return cells

static func _encode(img: Image, u: int, v: int, use_alpha: bool) -> int:
	var px := img.get_pixel(u, v)
	if use_alpha:
		return CellTypes.encode_rgb5551(px)
	return CellTypes.encode_rgb565(px)

# Dominant opaque color across an image, used to fill hidden/interior faces.
static func _fill_color(img: Image, use_alpha: bool) -> int:
	var counts := {}
	for u in range(img.get_width()):
		for v in range(img.get_height()):
			var px := img.get_pixel(u, v)
			if px.a < CellTypes.ALPHA_THRESHOLD:
				continue
			var e := CellTypes.encode_rgb5551(px) if use_alpha else CellTypes.encode_rgb565(px)
			counts[e] = counts.get(e, 0) + 1
	var best := 0
	var best_n := -1
	for k in counts:
		if counts[k] > best_n:
			best_n = counts[k]
			best = k
	if use_alpha:
		var fc := CellTypes.decode_color(best)
		return CellTypes.encode_rgb5551(Color(fc.r, fc.g, fc.b, 0.0))
	return best

# ─── transforms ──────────────────────────────────────────────────────────────
# Remap one cell's orientation + face-slot colors under a transform. Face slots
# are normal-based (CellTypes.slot_for_normal), so the solid tables move caps and
# legs correctly for prisms too. The HYPOTENUSE is the exception: its diagonal
# normal collapses under the Y>X>Z slot precedence, so its slot does NOT follow
# the axis-face table (e.g. ori 0's hyp (+X+Z) and ori 3's hyp (+X-Z) both live
# in FACE_RIGHT, while the table sends RIGHT to BACK under rotate_y). Move it
# explicitly from prism_hyp_slot(old ori) to prism_hyp_slot(new ori) — verified
# exact for all 12 orientations x 3 transforms, rot^4 == identity incl. slots
# (scratchpad/verify_remap.py).
static func _remap_cell(c: Array, orient_tab: Array, face_tab: Dictionary) -> Array:
	var nc := [c[0], c[1], c[2], c[3], c[4], c[5], c[6], c[7]]
	for f in range(CellTypes.FACE_TOP, CellTypes.FACE_BACK + 1):
		nc[face_tab[f]] = c[f]
	if c[0] == CellTypes.Type.PRISM:
		nc[1] = orient_tab[c[1]]
		nc[CellTypes.prism_hyp_slot(nc[1])] = c[CellTypes.prism_hyp_slot(c[1])]
	return nc

# 90 CCW about Y. Requires a square footprint (gx == gz).
static func rotate_y(cells: Array, gx: int, gy: int, gz: int) -> Array:
	var out := _new_cells(gx, gy, gz)
	for x in range(gx):
		for y in range(gy):
			for z in range(gz):
				var c: Array = cells[x][y][z]
				if c[0] == CellTypes.Type.EMPTY:
					continue
				var nx := z
				var nz := gx - 1 - x
				var nc := _remap_cell(c, ROT_ORIENT, ROT_FACE)
				out[nx][y][nz] = nc
	return out

# 90 about X. Requires gy == gz.
static func rotate_x(cells: Array, gx: int, gy: int, gz: int) -> Array:
	var out := _new_cells(gx, gy, gz)
	for x in range(gx):
		for y in range(gy):
			for z in range(gz):
				var c: Array = cells[x][y][z]
				if c[0] == CellTypes.Type.EMPTY:
					continue
				var ny := z
				var nz := gy - 1 - y
				var nc := _remap_cell(c, ROTX_ORIENT, ROTX_FACE)
				out[x][ny][nz] = nc
	return out

static func flip_vertical(cells: Array, gx: int, gy: int, gz: int) -> Array:
	var out := _new_cells(gx, gy, gz)
	for x in range(gx):
		for y in range(gy):
			for z in range(gz):
				var c: Array = cells[x][y][z]
				if c[0] == CellTypes.Type.EMPTY:
					continue
				var ny := gy - 1 - y
				var nc := _remap_cell(c, FLIP_ORIENT, FLIP_FACE)
				out[x][ny][z] = nc
	return out

# ─── RAMP 128x64 ─────────────────────────────────────────────────────────────
# Canonical: slope rises toward +X, tall wall at +X. Solid where y<x, Z-axis
# prism (ori 9) on the diagonal y==x, extruded along Z.
static func _build_ramp(img: Image, use_alpha: bool, gx: int, gy: int, gz: int) -> Array:
	var cells := _new_cells(gx, gy, gz)
	var F := gx
	var slope := img.get_region(Rect2i(0, 0, F, F))
	var back := img.get_region(Rect2i(F, 0, F, F))
	var bottom := img.get_region(Rect2i(F * 2, 0, F, F))
	var side_l := img.get_region(Rect2i(0, F, F, F))     # -Z end
	var side_r := img.get_region(Rect2i(F, F, F, F))      # +Z end
	var fill := _fill_color(slope, use_alpha)
	for x in range(F):
		for y in range(F):
			if y > x:
				continue
			for z in range(gz):
				if y < x:
					cells[x][y][z] = CellTypes.make_cell(CellTypes.Type.SOLID, 0, fill)
				else:
					# slope prism, monochrome from slope atlas (col z, row = step x)
					var col := _encode(slope, mini(z, F - 1), x, use_alpha)
					cells[x][y][z] = CellTypes.make_cell(CellTypes.Type.PRISM, 9, col)
	# paint flat faces 1:1
	for y in range(F):
		for z in range(gz):
			var zc: int = z if z < F else F - 1
			# +X wall (back)
			if cells[F - 1][y][z][0] == CellTypes.Type.SOLID:
				cells[F - 1][y][z][CellTypes.FACE_RIGHT] = _encode(back, F - 1 - zc, gy - 1 - y, use_alpha)
	for x in range(F):
		for z in range(gz):
			var zc2: int = z if z < F else F - 1
			if cells[x][0][z][0] == CellTypes.Type.SOLID:
				cells[x][0][z][CellTypes.FACE_BOTTOM] = _encode(bottom, x, F - 1 - zc2, use_alpha)
	# triangular ends
	for x in range(F):
		for y in range(F):
			if cells[x][y][0][0] != CellTypes.Type.EMPTY:
				cells[x][y][0][CellTypes.FACE_BACK] = _encode(side_l, x, gy - 1 - y, use_alpha)
			if cells[x][y][gz - 1][0] != CellTypes.Type.EMPTY:
				cells[x][y][gz - 1][CellTypes.FACE_FRONT] = _encode(side_r, x, gy - 1 - y, use_alpha)
	if use_alpha:
		_erase_transparent(cells, gx, gy, gz)
	return cells

# ─── GABLE 128x48 ────────────────────────────────────────────────────────────
# Canonical: ridge along Z at center. Left slope (x<F/2) ori 9, right slope ori 8.
# Half-height: peak at y=F/2.
static func _build_gable(img: Image, use_alpha: bool, gx: int, gy: int, gz: int) -> Array:
	var cells := _new_cells(gx, gy, gz)
	var F := gx
	var slope_a := img.get_region(Rect2i(0, 0, F, F / 2))       # left (-X) slope
	var slope_b := img.get_region(Rect2i(F, 0, F, F / 2))       # right (+X) slope
	var end_a := img.get_region(Rect2i(F * 2, 0, F, F / 2))     # -Z end
	var end_b := img.get_region(Rect2i(F * 3, 0, F, F / 2))     # +Z end
	var bottom := img.get_region(Rect2i(0, F / 2, F, F))
	var fill := _fill_color(bottom, use_alpha)
	for x in range(F):
		var d: int = x if x < F / 2 else (F - 1 - x)
		var ori: int = 9 if x < F / 2 else 8
		for y in range(F):
			if y > d:
				continue
			for z in range(gz):
				if y < d:
					cells[x][y][z] = CellTypes.make_cell(CellTypes.Type.SOLID, 0, fill)
				else:
					# slope prism color from slope atlas (col z, row = step d)
					var satlas := slope_a if x < F / 2 else slope_b
					var col := _encode(satlas, mini(z, F - 1), d, use_alpha)
					cells[x][y][z] = CellTypes.make_cell(CellTypes.Type.PRISM, ori, col)
	for x in range(F):
		for z in range(gz):
			if cells[x][0][z][0] == CellTypes.Type.SOLID:
				cells[x][0][z][CellTypes.FACE_BOTTOM] = _encode(bottom, x, F - 1 - mini(z, F - 1), use_alpha)
	for x in range(F):
		for y in range(F / 2):
			if cells[x][y][0][0] != CellTypes.Type.EMPTY:
				cells[x][y][0][CellTypes.FACE_BACK] = _encode(end_a, x, F / 2 - 1 - y, use_alpha)
			if cells[x][y][gz - 1][0] != CellTypes.Type.EMPTY:
				cells[x][y][gz - 1][CellTypes.FACE_FRONT] = _encode(end_b, x, F / 2 - 1 - y, use_alpha)
	if use_alpha:
		_erase_transparent(cells, gx, gy, gz)
	return cells

# ─── DIAGONAL WALL 112x32 ────────────────────────────────────────────────────
# Canonical: band along the NE-SW (x==z) diagonal, thickness DIAGWALL_T, full Y.
# lower-right boundary ori 3 (NW-solid), upper-left ori 1 (SE-solid).
static func _build_diagwall(img: Image, use_alpha: bool, gx: int, gy: int, gz: int) -> Array:
	var cells := _new_cells(gx, gy, gz)
	var F := gx
	var t := DIAGWALL_T
	var wall_a := img.get_region(Rect2i(0, 0, F, F))       # lower-right face (SE)
	var wall_b := img.get_region(Rect2i(F, 0, F, F))       # upper-left face (NW)
	var end_a := img.get_region(Rect2i(F * 2, 0, t, F))    # SW end (x=0 / z=0 borders)
	var end_b := img.get_region(Rect2i(F * 2 + t, 0, t, F))  # NE end
	var ribbon := img.get_region(Rect2i(F * 2 + 2 * t, 0, F, F))  # rows 0..t-1 top plan, t..2t-1 bottom plan
	var fill := _fill_color(wall_a, use_alpha)
	for x in range(F):
		for z in range(F):
			var dif := x - z
			if absi(dif) > t - 1:
				continue
			var ori := -1
			if dif == t - 1:
				ori = 3
			elif dif == -(t - 1):
				ori = 1
			# va: across-thickness index for the end faces. The band is 2t-1
			# diagonals wide but an end cell is only t wide, so ends stay 2:1.
			var va := (dif + t - 1) >> 1
			for y in range(gy):
				if ori < 0:
					cells[x][y][z] = CellTypes.make_cell(CellTypes.Type.SOLID, 0, fill)
				else:
					var atlas := wall_a if ori == 3 else wall_b
					# step index along the diagonal
					var step: int = mini(x, z)
					cells[x][y][z] = CellTypes.make_cell(CellTypes.Type.PRISM, ori, _encode(atlas, step, gy - 1 - y, use_alpha))
				# end faces where the band meets the footprint borders; u across
				# thickness, mirrored on the NE end so both read facing outward.
				# Guarded so a boundary prism's hyp slot (its wall sample) is
				# never clobbered — those prisms have no face on the border plane.
				if z == 0 and _end_slot_ok(cells[x][y][z], CellTypes.FACE_BACK):
					cells[x][y][z][CellTypes.FACE_BACK] = _encode(end_a, va, gy - 1 - y, use_alpha)
				if x == 0 and _end_slot_ok(cells[x][y][z], CellTypes.FACE_LEFT):
					cells[x][y][z][CellTypes.FACE_LEFT] = _encode(end_a, va, gy - 1 - y, use_alpha)
				if z == F - 1 and _end_slot_ok(cells[x][y][z], CellTypes.FACE_FRONT):
					cells[x][y][z][CellTypes.FACE_FRONT] = _encode(end_b, t - 1 - va, gy - 1 - y, use_alpha)
				if x == F - 1 and _end_slot_ok(cells[x][y][z], CellTypes.FACE_RIGHT):
					cells[x][y][z][CellTypes.FACE_RIGHT] = _encode(end_b, t - 1 - va, gy - 1 - y, use_alpha)
			# Ribbon is a top-down PLAN of the band: texel (x,z) is the top of cell
			# (x,z). The band therefore appears diagonally in the atlas exactly as
			# seen from above — no shear, and trivially 1:1 (one texel per top
			# face). The bottom shares the same texel (top-wins, like the shape
			# caps), since a wall's underside is rarely seen.
			cells[x][gy - 1][z][CellTypes.FACE_TOP] = _encode(ribbon, x, z, use_alpha)
			cells[x][0][z][CellTypes.FACE_BOTTOM] = _encode(ribbon, x, z, use_alpha)
	if use_alpha:
		_erase_transparent(cells, gx, gy, gz)
	return cells

# True if writing `slot` on this cell can't clobber a prism's hypotenuse sample.
static func _end_slot_ok(cell: Array, slot: int) -> bool:
	return cell[0] != CellTypes.Type.PRISM or CellTypes.prism_hyp_slot(cell[1]) != slot

# ─── DIAMOND 96x32 / CHAMFERED 144x32 (generalized chamfered box) ────────────
# c = chamfer. axis face width aw = F-2c. Corners are Y-axis prisms.
static func _build_chamfered_box(img: Image, c: int, use_alpha: bool, gx: int, gy: int, gz: int) -> Array:
	var cells := _new_cells(gx, gy, gz)
	var F := gx
	var aw := F - 2 * c
	# slice the strip: cap is the last F columns; the strip precedes it
	var cap := img.get_region(Rect2i(img.get_width() - F, 0, F, F))
	var fill := _fill_color(cap, use_alpha)
	var ox := (gx - F) / 2
	var oz := (gz - F) / 2
	# footprint: solid inside octagon, prism on the 4 chamfer edges
	for lx in range(F):
		for lz in range(F):
			var x := ox + lx
			var z := oz + lz
			var corner := -1
			var inside := true
			if lx + lz < c:
				inside = false
				if lx + lz == c - 1: corner = 0
			elif (F - 1 - lx) + lz < c:
				inside = false
				if (F - 1 - lx) + lz == c - 1: corner = 1
			elif (F - 1 - lx) + (F - 1 - lz) < c:
				inside = false
				if (F - 1 - lx) + (F - 1 - lz) == c - 1: corner = 2
			elif lx + (F - 1 - lz) < c:
				inside = false
				if lx + (F - 1 - lz) == c - 1: corner = 3
			for y in range(gy):
				if inside:
					cells[x][y][z] = CellTypes.make_cell(CellTypes.Type.SOLID, 0, fill)
				elif corner >= 0:
					var ori: int
					match corner:      # footprint corner -> solid points to center
						0: ori = 2
						1: ori = 3
						2: ori = 0
						_: ori = 1
					cells[x][y][z] = CellTypes.make_cell(CellTypes.Type.PRISM, ori, fill)
	# paint the strip. widths: axis aw, diagonal c, alternating, CCW from +X.
	var col := 0
	if aw > 0:
		# order E,NE,N,NW,W,SW,S,SE
		col = _paint_box_axis(cells, img, col, aw, CellTypes.FACE_RIGHT, ox, oz, F, gy, use_alpha, 0)
		col = _paint_box_diag(cells, img, col, c, 2, ox, oz, F, gy, use_alpha)
		col = _paint_box_axis(cells, img, col, aw, CellTypes.FACE_FRONT, ox, oz, F, gy, use_alpha, 3)
		col = _paint_box_diag(cells, img, col, c, 3, ox, oz, F, gy, use_alpha)
		col = _paint_box_axis(cells, img, col, aw, CellTypes.FACE_LEFT, ox, oz, F, gy, use_alpha, 1)
		col = _paint_box_diag(cells, img, col, c, 0, ox, oz, F, gy, use_alpha)
		col = _paint_box_axis(cells, img, col, aw, CellTypes.FACE_BACK, ox, oz, F, gy, use_alpha, 2)
		col = _paint_box_diag(cells, img, col, c, 1, ox, oz, F, gy, use_alpha)
	else:
		# diamond: only 4 diagonal faces, CCW from NE
		col = _paint_box_diag(cells, img, col, c, 2, ox, oz, F, gy, use_alpha)
		col = _paint_box_diag(cells, img, col, c, 3, ox, oz, F, gy, use_alpha)
		col = _paint_box_diag(cells, img, col, c, 0, ox, oz, F, gy, use_alpha)
		col = _paint_box_diag(cells, img, col, c, 1, ox, oz, F, gy, use_alpha)
	# caps — corner prisms included: their top/bottom triangles show the cap
	# design (same indexing as the neighboring solids), lateral slots keep the
	# strip sample painted above.
	for lx in range(F):
		for lz in range(F):
			var x := ox + lx
			var z := oz + lz
			if cells[x][0][z][0] != CellTypes.Type.EMPTY:
				cells[x][0][z][CellTypes.FACE_BOTTOM] = _encode(cap, lx, F - 1 - lz, use_alpha)
			if cells[x][gy - 1][z][0] != CellTypes.Type.EMPTY:
				cells[x][gy - 1][z][CellTypes.FACE_TOP] = _encode(cap, lx, lz, use_alpha)
	if use_alpha:
		_erase_transparent(cells, gx, gy, gz)
	return cells

static func _paint_box_axis(cells: Array, img: Image, col: int, w: int, face_idx: int, ox: int, oz: int, F: int, gy: int, use_alpha: bool, side: int) -> int:
	var c := (F - w) / 2
	for i in range(w):
		for v in range(gy):
			var e := _encode(img, col + i, gy - 1 - v, use_alpha)
			var pos: Vector3i
			match side:
				0: pos = Vector3i(ox + F - 1, v, oz + c + i)          # +X
				3: pos = Vector3i(ox + F - 1 - c - i, v, oz + F - 1)  # +Z
				1: pos = Vector3i(ox, v, oz + F - 1 - c - i)          # -X
				_: pos = Vector3i(ox + c + i, v, oz)                  # -Z
			cells[pos.x][pos.y][pos.z][face_idx] = e
	return col + w

static func _paint_box_diag(cells: Array, img: Image, col: int, c: int, corner: int, ox: int, oz: int, F: int, gy: int, use_alpha: bool) -> int:
	var positions: Array = []
	for lx in range(F):
		for lz in range(F):
			var on := false
			match corner:
				0: on = (lx + lz == c - 1)
				1: on = ((F - 1 - lx) + lz == c - 1)
				2: on = ((F - 1 - lx) + (F - 1 - lz) == c - 1)
				_: on = (lx + (F - 1 - lz) == c - 1)
			if on:
				positions.append(Vector2i(ox + lx, oz + lz))
	match corner:
		0: positions.sort_custom(func(a, b): return a.x < b.x)
		1: positions.sort_custom(func(a, b): return a.x > b.x)
		2: positions.sort_custom(func(a, b): return a.x > b.x)
		_: positions.sort_custom(func(a, b): return a.x < b.x)
	for idx in range(positions.size()):
		var p: Vector2i = positions[idx]
		for y in range(gy):
			var ci := _encode(img, col + idx, gy - 1 - y, use_alpha)
			# Strip sample on every slot; the caps loop afterwards overwrites
			# FACE_TOP / FACE_BOTTOM on the end layers with the cap design.
			var pc: Array = cells[p.x][y][p.y]
			for fi in range(CellTypes.FACE_TOP, CellTypes.FACE_BACK + 1):
				pc[fi] = ci
	return col + c

# ─── CROSS 160x32 ────────────────────────────────────────────────────────────
# Plus cross-section: central band + arms, pure cubes. Full Y.
static func _build_cross(img: Image, use_alpha: bool, gx: int, gy: int, gz: int) -> Array:
	var cells := _new_cells(gx, gy, gz)
	var F := gx
	var lo := (F - CROSS_ARM) / 2       # 8
	var hi := lo + CROSS_ARM             # 24
	var cap := img.get_region(Rect2i(F * 4, 0, F, F))
	var fill := _fill_color(cap, use_alpha)
	for x in range(F):
		for z in range(F):
			if (x >= lo and x < hi) or (z >= lo and z < hi):
				for y in range(gy):
					cells[x][y][z] = CellTypes.make_cell(CellTypes.Type.SOLID, 0, fill)
	# caps
	for x in range(F):
		for z in range(F):
			if cells[x][0][z][0] == CellTypes.Type.SOLID:
				cells[x][0][z][CellTypes.FACE_BOTTOM] = _encode(cap, x, F - 1 - z, use_alpha)
			if cells[x][gy - 1][z][0] == CellTypes.Type.SOLID:
				cells[x][gy - 1][z][CellTypes.FACE_TOP] = _encode(cap, x, z, use_alpha)
	# Vertical sides: the atlas's leading strip (cols 0..127) is the perimeter of
	# the plus unrolled CCW from the +X arm end: 16,8,8,16,8,8,16,8,8,16,8,8. Each
	# of the 12 segments maps 1:1 onto one run of exposed side faces (full height).
	# Row [col0, width, x0, dx, z0, dz, face_slot]; cell = (x0+dx*i, z0+dz*i).
	var strip := img.get_region(Rect2i(0, 0, F * 4, F))
	var sides := [
		[0, 16, 31, 0, 23, -1, CellTypes.FACE_RIGHT],
		[16, 8, 31, -1, 8, 0, CellTypes.FACE_BACK],
		[24, 8, 23, 0, 7, -1, CellTypes.FACE_RIGHT],
		[32, 16, 23, -1, 0, 0, CellTypes.FACE_BACK],
		[48, 8, 8, 0, 0, 1, CellTypes.FACE_LEFT],
		[56, 8, 7, -1, 8, 0, CellTypes.FACE_BACK],
		[64, 16, 0, 0, 8, 1, CellTypes.FACE_LEFT],
		[80, 8, 0, 1, 23, 0, CellTypes.FACE_FRONT],
		[88, 8, 8, 0, 24, 1, CellTypes.FACE_LEFT],
		[96, 16, 8, 1, 31, 0, CellTypes.FACE_FRONT],
		[112, 8, 23, 0, 31, -1, CellTypes.FACE_RIGHT],
		[120, 8, 24, 1, 23, 0, CellTypes.FACE_FRONT],
	]
	for seg in sides:
		var c0: int = seg[0]
		var w: int = seg[1]
		var slot: int = seg[6]
		for i in range(w):
			var x: int = seg[2] + seg[3] * i
			var z: int = seg[4] + seg[5] * i
			for y in range(gy):
				if cells[x][y][z][0] == CellTypes.Type.SOLID:
					cells[x][y][z][slot] = _encode(strip, c0 + i, F - 1 - y, use_alpha)
	if use_alpha:
		_erase_transparent(cells, gx, gy, gz)
	return cells

# ─── PANEL / SLAB (thin flat cube, thickness t, flush to bottom) ─────────────
# Atlas: row1 top|bottom (32x32); then N|S then E|W, each 32 x t.
static func _build_slab(img: Image, t: int, use_alpha: bool, gx: int, gy: int, gz: int) -> Array:
	var cells := _new_cells(gx, gy, gz)
	var F := gx
	var top := img.get_region(Rect2i(0, 0, F, F))
	var bottom := img.get_region(Rect2i(F, 0, F, F))
	var n_img := img.get_region(Rect2i(0, F, F, t))       # +Z
	var s_img := img.get_region(Rect2i(F, F, F, t))       # -Z
	var e_img := img.get_region(Rect2i(0, F + t, F, t))   # +X
	var w_img := img.get_region(Rect2i(F, F + t, F, t))   # -X
	var fill := _fill_color(top, use_alpha)
	for x in range(F):
		for y in range(t):
			for z in range(F):
				cells[x][y][z] = CellTypes.make_cell(CellTypes.Type.SOLID, 0, fill)
	for x in range(F):
		for z in range(F):
			cells[x][t - 1][z][CellTypes.FACE_TOP] = _encode(top, x, F - 1 - z, use_alpha)
			cells[x][0][z][CellTypes.FACE_BOTTOM] = _encode(bottom, x, F - 1 - z, use_alpha)
	for y in range(t):
		for z in range(F):
			cells[F - 1][y][z][CellTypes.FACE_RIGHT] = _encode(e_img, z, t - 1 - y, use_alpha)
			cells[0][y][z][CellTypes.FACE_LEFT] = _encode(w_img, z, t - 1 - y, use_alpha)
	for y in range(t):
		for x in range(F):
			cells[x][y][F - 1][CellTypes.FACE_FRONT] = _encode(n_img, x, t - 1 - y, use_alpha)
			cells[x][y][0][CellTypes.FACE_BACK] = _encode(s_img, x, t - 1 - y, use_alpha)
	if use_alpha:
		_erase_transparent(cells, gx, gy, gz)
	return cells

# ─── STAIRS (n equal steps climbing +X, extruded along Z) ────────────────────
static func _build_stairs(img: Image, nsteps: int, use_alpha: bool, gx: int, gy: int, gz: int) -> Array:
	var cells := _new_cells(gx, gy, gz)
	var F := gx
	var ss := F / nsteps
	var tread: Image
	var riser: Image
	var back: Image
	var bottom: Image
	var side: Image
	if nsteps == 2:
		tread = img.get_region(Rect2i(0, 0, ss, F))
		riser = img.get_region(Rect2i(ss, 0, ss, F))
		back = img.get_region(Rect2i(ss * 2, 0, F, F))
		bottom = img.get_region(Rect2i(ss * 2 + F, 0, F, F))
		side = img.get_region(Rect2i(ss * 2 + F * 2, 0, F, F))
	else:
		tread = img.get_region(Rect2i(0, 0, ss, F))
		riser = img.get_region(Rect2i(ss, 0, ss, F))
		back = img.get_region(Rect2i(ss * 2, 0, F, F))
		bottom = img.get_region(Rect2i(ss * 2 + F, 0, F, F))
		side = img.get_region(Rect2i(0, F, F, F))
	var fill := _fill_color(bottom, use_alpha)
	for x in range(F):
		var i := x / ss
		var top_h := (i + 1) * ss
		for y in range(top_h):
			for z in range(gz):
				cells[x][y][z] = CellTypes.make_cell(CellTypes.Type.SOLID, 0, fill)
	# paint faces
	for x in range(F):
		for y in range(gy):
			for z in range(gz):
				if cells[x][y][z][0] != CellTypes.Type.SOLID:
					continue
				# Per-step half-brick stagger: consecutive steps sample the shared
				# tread/riser strip shifted by ss along z, so the coursing runs as
				# a staggered running bond climbing the stair instead of a stack
				# bond with joints lining up between steps.
				var i := x / ss
				var so := (i % 2) * ss
				# top face where nothing above -> tread (plan view of one step
				# strip: u 0 = riser edge, v = F-1-z north-up like slab tops)
				if y + 1 >= gy or cells[x][y + 1][z][0] == CellTypes.Type.EMPTY:
					cells[x][y][z][CellTypes.FACE_TOP] = _encode(tread, x % ss, (F - 1 - z + so) % F, use_alpha)
				# -X face where nothing to the left -> riser (elevation rotated
				# 90°: cell column = height within the step, row = z)
				if x == 0 or cells[x - 1][y][z][0] == CellTypes.Type.EMPTY:
					cells[x][y][z][CellTypes.FACE_LEFT] = _encode(riser, y % ss, (z + so) % F, use_alpha)
				# +X wall at back
				if x == F - 1:
					cells[x][y][z][CellTypes.FACE_RIGHT] = _encode(back, F - 1 - z, F - 1 - y, use_alpha)
				# bottom
				if y == 0:
					cells[x][y][z][CellTypes.FACE_BOTTOM] = _encode(bottom, x, F - 1 - z, use_alpha)
				# side profile (both Z ends)
				if z == 0:
					cells[x][y][z][CellTypes.FACE_BACK] = _encode(side, x, F - 1 - y, use_alpha)
				if z == gz - 1:
					cells[x][y][z][CellTypes.FACE_FRONT] = _encode(side, x, F - 1 - y, use_alpha)
	if use_alpha:
		_erase_transparent(cells, gx, gy, gz)
	return cells

# ─── octagon helpers (shared by pipe) ────────────────────────────────────────
static func _oct_inside(lx: int, lz: int, F: int, c: int) -> bool:
	if lx + lz < c: return false
	if (F - 1 - lx) + lz < c: return false
	if (F - 1 - lx) + (F - 1 - lz) < c: return false
	if lx + (F - 1 - lz) < c: return false
	return true

static func _oct_corner_edge(lx: int, lz: int, F: int, c: int) -> int:
	if lx + lz == c - 1: return 0
	if (F - 1 - lx) + lz == c - 1: return 1
	if (F - 1 - lx) + (F - 1 - lz) == c - 1: return 2
	if lx + (F - 1 - lz) == c - 1: return 3
	return -1

# ─── PIPE QUARTER (one 32x32 quadrant of a 64x64 hollow octagon ring) ────────
# Outer octagon F=64 c=19; bore octagon inset 2, c=19. Extruded along Y.
# Four Y-rotations of this block close the ring.
static func _build_pipe_quarter(img: Image, use_alpha: bool, gx: int, gy: int, gz: int) -> Array:
	var cells := _new_cells(gx, gy, gz)
	var RF := 64
	var C := 19
	var inset := 2
	var Fin := RF - 2 * inset
	# atlas: outer-arc(45) | inner-arc(41) | end-ring(32) | cut(2)
	var outer_arc := img.get_region(Rect2i(0, 0, 45, 32))
	var inner_arc := img.get_region(Rect2i(45, 0, 41, 32))
	var end_ring := img.get_region(Rect2i(86, 0, 32, 32))
	var fill := _fill_color(end_ring, use_alpha)
	# Build the full ring cross-section (type + orient), then take the SW quadrant.
	# The two diagonal-wall surfaces are BOTH prism planes: the outer chamfer edge
	# sits just OUTSIDE the outer octagon body (like the octagon builder's corner
	# cells), and the inner chamfer edge is the bore surface.
	var out_map := {0: 2, 1: 3, 2: 0, 3: 1}   # outer: solid points inward
	for lx in range(gx):        # SW quadrant only
		for lz in range(gz):
			var ix := lx - inset
			var iz := lz - inset
			var cell_type := CellTypes.Type.EMPTY
			var orient := 0
			var oe := _oct_corner_edge(lx, lz, RF, C)
			if oe >= 0:
				# outer diagonal surface (outside the octagon body)
				cell_type = CellTypes.Type.PRISM
				orient = out_map[oe]
			elif _oct_inside(lx, lz, RF, C):
				var in_bore := ix >= 0 and ix < Fin and iz >= 0 and iz < Fin and _oct_inside(ix, iz, Fin, C)
				if not in_bore:
					cell_type = CellTypes.Type.SOLID
					var ie := -1
					if ix >= 0 and iz >= 0:
						ie = _oct_corner_edge(ix, iz, Fin, C)
					if ie >= 0:
						cell_type = CellTypes.Type.PRISM
						orient = ie   # bore: solid points outward -> corner itself
			if cell_type != CellTypes.Type.EMPTY:
				for y in range(gy):
					cells[lx][y][lz] = CellTypes.make_cell(cell_type, orient, fill)
	# Arc walls, 1:1 along the unrolled perimeters (v = gy-1-y). The quadrant's
	# outer surface is south flat (13) + SW diagonal (19) + west flat (13) = 45
	# columns; the bore surface is 11 + 19 + 11 = 41 — exactly the two arc cells'
	# widths. Both walks run in the same rotational direction (from the +X-side
	# cut toward the +Z-side cut), so four Y-rotations tile the texture
	# continuously around the ring. Diagonal runs paint the prisms' hyp slots.
	var u := 0
	for lx in range(31, 18, -1):                       # outer south flat, -Z faces
		_paint_pipe_col(cells, gy, lx, 0, CellTypes.FACE_BACK, outer_arc, u, use_alpha)
		u += 1
	for i in range(19):                                # outer SW diagonal prisms
		var px := 18 - i
		var pz := i
		_paint_pipe_col(cells, gy, px, pz, CellTypes.prism_hyp_slot(cells[px][0][pz][1]), outer_arc, u, use_alpha)
		u += 1
	for lz in range(19, 32):                           # outer west flat, -X faces
		_paint_pipe_col(cells, gy, 0, lz, CellTypes.FACE_LEFT, outer_arc, u, use_alpha)
		u += 1
	u = 0
	for lx in range(31, 20, -1):                       # bore south flat, faces +Z into bore
		_paint_pipe_col(cells, gy, lx, 1, CellTypes.FACE_FRONT, inner_arc, u, use_alpha)
		u += 1
	for i in range(19):                                # bore SW diagonal prisms
		var bx := 20 - i
		var bz := 2 + i
		_paint_pipe_col(cells, gy, bx, bz, CellTypes.prism_hyp_slot(cells[bx][0][bz][1]), inner_arc, u, use_alpha)
		u += 1
	for lz in range(21, 32):                           # bore west flat, faces +X into bore
		_paint_pipe_col(cells, gy, 1, lz, CellTypes.FACE_RIGHT, inner_arc, u, use_alpha)
		u += 1
	# Radial cut faces — exposed only when the quarter stands alone (interior once
	# rotated into a ring). The wall is `inset` voxels thick, matching the 2-wide
	# cut cell: +X end at lx=gx-1, +Z end at lz=gz-1, u = radial index (0 outer).
	var cut := img.get_region(Rect2i(118, 0, 2, 32))
	for y in range(gy):
		for r in range(inset):
			if cells[gx - 1][y][r][0] != CellTypes.Type.EMPTY:
				cells[gx - 1][y][r][CellTypes.FACE_RIGHT] = _encode(cut, r, gy - 1 - y, use_alpha)
			if cells[r][y][gz - 1][0] != CellTypes.Type.EMPTY:
				cells[r][y][gz - 1][CellTypes.FACE_FRONT] = _encode(cut, r, gy - 1 - y, use_alpha)
	# caps from end-ring cell (approximate; ring texels used, corners ignored).
	# Prisms included: their top/bottom triangles show the end-ring design.
	for lx in range(gx):
		for lz in range(gz):
			if cells[lx][0][lz][0] != CellTypes.Type.EMPTY:
				cells[lx][0][lz][CellTypes.FACE_BOTTOM] = _encode(end_ring, lx, 31 - lz, use_alpha)
			if cells[lx][gy - 1][lz][0] != CellTypes.Type.EMPTY:
				cells[lx][gy - 1][lz][CellTypes.FACE_TOP] = _encode(end_ring, lx, lz, use_alpha)
	if use_alpha:
		_erase_transparent(cells, gx, gy, gz)
	return cells

# Paint one full-height wall column of the pipe with atlas column u (v rises
# downward from the top of the cell, v = gy-1-y).
static func _paint_pipe_col(cells: Array, gy: int, x: int, z: int, slot: int, atlas: Image, u: int, use_alpha: bool) -> void:
	for y in range(gy):
		if cells[x][y][z][0] != CellTypes.Type.EMPTY:
			cells[x][y][z][slot] = _encode(atlas, u, gy - 1 - y, use_alpha)

# ─── shared ──────────────────────────────────────────────────────────────────
static func _erase_transparent(cells: Array, gx: int, gy: int, gz: int) -> void:
	for x in range(gx):
		for y in range(gy):
			for z in range(gz):
				var cell: Array = cells[x][y][z]
				if cell[0] == CellTypes.Type.EMPTY:
					continue
				if cell[0] == CellTypes.Type.PRISM:
					if CellTypes.is_rgb5551(cell[2]) and CellTypes.decode_rgb5551(cell[2]).a < CellTypes.ALPHA_THRESHOLD:
						cells[x][y][z] = CellTypes.empty_cell()
					continue
				var all_t := true
				for fi in range(CellTypes.FACE_TOP, CellTypes.FACE_BACK + 1):
					var cv: int = cell[fi]
					if not CellTypes.is_rgb5551(cv) or CellTypes.decode_rgb5551(cv).a >= CellTypes.ALPHA_THRESHOLD:
						all_t = false
						break
				if all_t:
					cells[x][y][z] = CellTypes.empty_cell()
