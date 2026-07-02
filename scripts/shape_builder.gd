class_name ShapeBuilder
# Builds predefined prism shapes (ramp, gable, diagonal wall, diamond, chamfered
# cube, cross, chamfered opening) from an exact-size 1:1 atlas into a cell grid.
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
const OPENING_CHAMFER := 8

# Y-rotation 90 CCW: source(x,z) -> dest(z, N-1-x). Faces: +X->-Z, +Z->+X, etc.
const ROT_ORIENT := [3, 0, 1, 2, 8, 11, 10, 9, 7, 4, 5, 6]
# face index (2..7) remap under one CCW turn
const ROT_FACE := {2: 2, 3: 3, 4: 7, 5: 6, 6: 4, 7: 5}
# Vertical flip (y -> N-1-y): top<->bottom, prism corners mirror.
const FLIP_ORIENT := [0, 1, 2, 3, 5, 4, 7, 6, 11, 10, 9, 8]
const FLIP_FACE := {2: 3, 3: 2, 4: 4, 5: 5, 6: 6, 7: 7}

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
		"opening": cells = _build_opening(img, use_alpha, gx, gy, gz)
		_: return _new_cells(gx, gy, gz)

	var facing: int = opt.get("facing", 0)
	for i in range(facing % 4):
		cells = rotate_y(cells, gx, gy, gz)
	if opt.get("inverted", false):
		cells = flip_vertical(cells, gx, gy, gz)
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
				var nc := [c[0], c[1], c[2], c[3], c[4], c[5], c[6], c[7]]
				if c[0] == CellTypes.Type.PRISM:
					nc[1] = ROT_ORIENT[c[1]]
					# prisms are monochrome (color in slot 2) — nothing else to remap
				else:
					for f in range(CellTypes.FACE_TOP, CellTypes.FACE_BACK + 1):
						nc[ROT_FACE[f]] = c[f]
				out[nx][y][nz] = nc
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
				var nc := [c[0], c[1], c[2], c[3], c[4], c[5], c[6], c[7]]
				if c[0] == CellTypes.Type.PRISM:
					nc[1] = FLIP_ORIENT[c[1]]
				else:
					for f in range(CellTypes.FACE_TOP, CellTypes.FACE_BACK + 1):
						nc[FLIP_FACE[f]] = c[f]
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
			for y in range(gy):
				if ori < 0:
					cells[x][y][z] = CellTypes.make_cell(CellTypes.Type.SOLID, 0, fill)
				else:
					var atlas := wall_a if ori == 3 else wall_b
					# step index along the diagonal
					var step: int = mini(x, z)
					cells[x][y][z] = CellTypes.make_cell(CellTypes.Type.PRISM, ori, _encode(atlas, step, gy - 1 - y, use_alpha))
	if use_alpha:
		_erase_transparent(cells, gx, gy, gz)
	return cells

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
	# caps
	for lx in range(F):
		for lz in range(F):
			var x := ox + lx
			var z := oz + lz
			if cells[x][0][z][0] == CellTypes.Type.SOLID:
				cells[x][0][z][CellTypes.FACE_BOTTOM] = _encode(cap, lx, F - 1 - lz, use_alpha)
			if cells[x][gy - 1][z][0] == CellTypes.Type.SOLID:
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
			cells[p.x][y][p.y][2] = _encode(img, col + idx, gy - 1 - y, use_alpha)
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
	if use_alpha:
		_erase_transparent(cells, gx, gy, gz)
	return cells

# ─── CHAMFERED OPENING 224x32 ────────────────────────────────────────────────
# Canonical: chamfer on the +Z (front) top edge, depth OPENING_CHAMFER.
# Bevel = X-axis prism ori 4, extruded along X.
static func _build_opening(img: Image, use_alpha: bool, gx: int, gy: int, gz: int) -> Array:
	var cells := _new_cells(gx, gy, gz)
	var F := gx
	var d := OPENING_CHAMFER
	var front := img.get_region(Rect2i(0, 0, F, F - d))
	var chamfer := img.get_region(Rect2i(F, 0, F, d))
	var top := img.get_region(Rect2i(F * 2, 0, F, F - d))
	var back := img.get_region(Rect2i(F * 3, 0, F, F))
	var bottom := img.get_region(Rect2i(F * 4, 0, F, F))
	var fill := _fill_color(back, use_alpha)
	for z in range(F):
		for y in range(F):
			var m := (F - 1 - y) + (F - 1 - z)   # dist from top-front corner
			var carved := (y >= F - d and m < d)
			if carved and m != d - 1:
				continue   # removed
			for x in range(gx):
				if carved and m == d - 1:
					cells[x][y][z] = CellTypes.make_cell(CellTypes.Type.PRISM, 4, _encode(chamfer, gx - 1 - x, (d - 1) - (F - 1 - z), use_alpha))
				else:
					cells[x][y][z] = CellTypes.make_cell(CellTypes.Type.SOLID, 0, fill)
	# flat faces
	for x in range(gx):
		for y in range(F - d):
			# front (+Z at z=F-1) for lower part
			if cells[x][y][F - 1][0] == CellTypes.Type.SOLID:
				cells[x][y][F - 1][CellTypes.FACE_FRONT] = _encode(front, x, F - d - 1 - y, use_alpha)
			# back (-Z at z=0)
			if cells[x][y][0][0] == CellTypes.Type.SOLID:
				cells[x][y][0][CellTypes.FACE_BACK] = _encode(back, gx - 1 - x, F - 1 - y, use_alpha)
	for x in range(gx):
		for z in range(F):
			if cells[x][gy - 1][z][0] == CellTypes.Type.SOLID:
				cells[x][gy - 1][z][CellTypes.FACE_TOP] = _encode(top, x, F - 1 - z, use_alpha)
			if cells[x][0][z][0] == CellTypes.Type.SOLID:
				cells[x][0][z][CellTypes.FACE_BOTTOM] = _encode(bottom, x, F - 1 - z, use_alpha)
	# remaining upper-back rows for back face (y >= F-d)
	for x in range(gx):
		for y in range(F - d, F):
			if cells[x][y][0][0] == CellTypes.Type.SOLID:
				cells[x][y][0][CellTypes.FACE_BACK] = _encode(back, gx - 1 - x, F - 1 - y, use_alpha)
	if use_alpha:
		_erase_transparent(cells, gx, gy, gz)
	return cells

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
