class_name ShapeBuilder

# Shapes carry no texture. A single flat value fills every cell so the editor
# viewport has something to draw; it never reaches the exporter.
const FLAT := 0
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
static func build(shape: String, gx: int, gy: int, gz: int, opt: Dictionary = {}) -> Array:
	var cells: Array
	match shape:
		"ramp": cells = _build_ramp(gx, gy, gz)
		"gable": cells = _build_gable(gx, gy, gz)
		"diagwall": cells = _build_diagwall(gx, gy, gz)
		"diamond": cells = _build_chamfered_box(gx / 2, gx, gy, gz)
		"chamfered": cells = _build_chamfered_box(CHAMFER_COLUMN, gx, gy, gz)
		"cross": cells = _build_cross(gx, gy, gz)
		"panel": cells = _build_slab(1, gx, gy, gz)
		"slab_quarter": cells = _build_slab(8, gx, gy, gz)
		"slab_half": cells = _build_slab(16, gx, gy, gz)
		"stairs_4": cells = _build_stairs(4, gx, gy, gz)
		"pipe_quarter": cells = _build_pipe_quarter(gx, gy, gz)
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
static func _build_ramp(gx: int, gy: int, gz: int) -> Array:
	var cells := _new_cells(gx, gy, gz)
	var F := gx
	for x in range(F):
		for y in range(F):
			if y > x:
				continue
			for z in range(gz):
				if y < x:
					cells[x][y][z] = CellTypes.make_cell(CellTypes.Type.SOLID, 0, FLAT)
				else:
					cells[x][y][z] = CellTypes.make_cell(CellTypes.Type.PRISM, 9, FLAT)
	# paint flat faces 1:1
	for y in range(F):
		for z in range(gz):
			var zc: int = z if z < F else F - 1
			# +X wall (back)
	for x in range(F):
		for z in range(gz):
			var zc2: int = z if z < F else F - 1
	# triangular ends
	return cells

# ─── GABLE 128x48 ────────────────────────────────────────────────────────────
# Canonical: ridge along Z at center. Left slope (x<F/2) ori 9, right slope ori 8.
# Half-height: peak at y=F/2.
static func _build_gable(gx: int, gy: int, gz: int) -> Array:
	var cells := _new_cells(gx, gy, gz)
	var F := gx
	for x in range(F):
		var d: int = x if x < F / 2 else (F - 1 - x)
		var ori: int = 9 if x < F / 2 else 8
		for y in range(F):
			if y > d:
				continue
			for z in range(gz):
				if y < d:
					cells[x][y][z] = CellTypes.make_cell(CellTypes.Type.SOLID, 0, FLAT)
				else:
					cells[x][y][z] = CellTypes.make_cell(CellTypes.Type.PRISM, ori, FLAT)
	return cells

# ─── DIAGONAL WALL 112x32 ────────────────────────────────────────────────────
# Canonical: band along the NE-SW (x==z) diagonal, thickness DIAGWALL_T, full Y.
# lower-right boundary ori 3 (NW-solid), upper-left ori 1 (SE-solid).
static func _build_diagwall(gx: int, gy: int, gz: int) -> Array:
	var cells := _new_cells(gx, gy, gz)
	var F := gx
	var t := DIAGWALL_T
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
					cells[x][y][z] = CellTypes.make_cell(CellTypes.Type.SOLID, 0, FLAT)
				else:
					# step index along the diagonal
					var step: int = mini(x, z)
					cells[x][y][z] = CellTypes.make_cell(CellTypes.Type.PRISM, ori, FLAT)
				# end faces where the band meets the footprint borders; u across
				# thickness, mirrored on the NE end so both read facing outward.
				# Guarded so a boundary prism's hyp slot (its wall sample) is
				# never clobbered — those prisms have no face on the border plane.
			# Ribbon is a top-down PLAN of the band: texel (x,z) is the top of cell
			# (x,z). The band therefore appears diagonally in the atlas exactly as
			# seen from above — no shear, and trivially 1:1 (one texel per top
			# face). The bottom shares the same texel (top-wins, like the shape
			# caps), since a wall's underside is rarely seen.
	return cells
# ─── DIAMOND 96x32 / CHAMFERED 144x32 (generalized chamfered box) ────────────
# c = chamfer. axis face width aw = F-2c. Corners are Y-axis prisms.
static func _build_chamfered_box(c: int, gx: int, gy: int, gz: int) -> Array:
	var cells := _new_cells(gx, gy, gz)
	var F := gx
	var aw := F - 2 * c
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
					cells[x][y][z] = CellTypes.make_cell(CellTypes.Type.SOLID, 0, FLAT)
				elif corner >= 0:
					var ori: int
					match corner:      # footprint corner -> solid points to center
						0: ori = 2
						1: ori = 3
						2: ori = 0
						_: ori = 1
					cells[x][y][z] = CellTypes.make_cell(CellTypes.Type.PRISM, ori, FLAT)
	# caps — corner prisms included: their top/bottom triangles show the cap
	# design (same indexing as the neighboring solids), lateral slots keep the
	for lx in range(F):
		for lz in range(F):
			var x := ox + lx
			var z := oz + lz
	return cells
# ─── CROSS 160x32 ────────────────────────────────────────────────────────────
# Plus cross-section: central band + arms, pure cubes. Full Y.
static func _build_cross(gx: int, gy: int, gz: int) -> Array:
	var cells := _new_cells(gx, gy, gz)
	var F := gx
	var lo := (F - CROSS_ARM) / 2       # 8
	var hi := lo + CROSS_ARM             # 24
	for x in range(F):
		for z in range(F):
			if (x >= lo and x < hi) or (z >= lo and z < hi):
				for y in range(gy):
					cells[x][y][z] = CellTypes.make_cell(CellTypes.Type.SOLID, 0, FLAT)
	# caps
	# Vertical sides: the atlas's leading strip (cols 0..127) is the perimeter of
	# the plus unrolled CCW from the +X arm end: 16,8,8,16,8,8,16,8,8,16,8,8. Each
	# of the 12 segments maps 1:1 onto one run of exposed side faces (full height).
	# Row [col0, width, x0, dx, z0, dz, face_slot]; cell = (x0+dx*i, z0+dz*i).
	return cells

# ─── PANEL / SLAB (thin flat cube, thickness t, flush to bottom) ─────────────
# Atlas: row1 top|bottom (32x32); then N|S then E|W, each 32 x t.
static func _build_slab(t: int, gx: int, gy: int, gz: int) -> Array:
	var cells := _new_cells(gx, gy, gz)
	var F := gx
	for x in range(F):
		for y in range(t):
			for z in range(F):
				cells[x][y][z] = CellTypes.make_cell(CellTypes.Type.SOLID, 0, FLAT)
	return cells

# ─── STAIRS (n equal steps climbing +X, extruded along Z) ────────────────────
static func _build_stairs(nsteps: int, gx: int, gy: int, gz: int) -> Array:
	var cells := _new_cells(gx, gy, gz)
	var F := gx
	var ss := F / nsteps
	for x in range(F):
		var i := x / ss
		var top_h := (i + 1) * ss
		for y in range(top_h):
			for z in range(gz):
				cells[x][y][z] = CellTypes.make_cell(CellTypes.Type.SOLID, 0, FLAT)
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
				# -X face where nothing to the left -> riser (elevation rotated
				# 90°: cell column = height within the step, row = z)
				# +X wall at back
				# bottom
				# side profile (both Z ends)
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
static func _build_pipe_quarter(gx: int, gy: int, gz: int) -> Array:
	var cells := _new_cells(gx, gy, gz)
	var RF := 64
	var C := 19
	var inset := 2
	var Fin := RF - 2 * inset
	# atlas: outer-arc(45) | inner-arc(41) | end-ring(32) | cut(2)
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
					cells[lx][y][lz] = CellTypes.make_cell(cell_type, orient, FLAT)
	return cells
