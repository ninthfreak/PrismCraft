class_name BlockImporter
# Single source of truth for turning a validated block texture into a cell grid.
# Both the GUI (Import Block Texture) and the headless batch exporter call
# build_cells(), so manual and batch import can never drift. Shape layouts
# delegate to ShapeBuilder; octagon and cube (uniform/capped/net) geometry lives
# here. Every function is static and free of scene/UI state.

const SHAPE_LAYOUTS := ["ramp", "gable", "diagwall", "diamond", "chamfered",
	"cross", "panel", "slab_quarter", "slab_half",
	"stairs_2", "stairs_4", "pipe_quarter"]

# ─── entry point ─────────────────────────────────────────────────────────────
# layout: a string returned by CellTypes.validate_block_texture (non-empty).
# opt: shape orientation options (ignored by cube/octagon). Returns a fresh grid.
static func build_cells(layout: String, image: Image, gx: int, gy: int, gz: int, opt: Dictionary = {}) -> Array:
	var use_alpha := CellTypes.image_has_alpha(image)
	if layout in SHAPE_LAYOUTS:
		return ShapeBuilder.build(layout, image, use_alpha, gx, gy, gz, opt)
	if layout == "octagon_full" or layout == "octagon_half":
		var fp := octagon_footprint(layout, gx)
		return build_octagon(slice_faces(image, layout, gx, gy), fp, gx, gy, gz, use_alpha)
	return build_cube(slice_faces(image, layout, gx, gy), use_alpha, gx, gy, gz)

static func octagon_footprint(layout: String, gx: int) -> int:
	return gx if layout == "octagon_full" else gx / 2

# Default orientation for batch import (matches the first preview entry).
static func default_opt(_layout: String) -> Dictionary:
	return {}

# ─── atlas slicing (cube + octagon) ──────────────────────────────────────────
static func slice_faces(image: Image, layout: String, gx: int, gy: int) -> Dictionary:
	var faces := {}
	var tw := gx
	var th := gy
	if layout == "octagon_full" or layout == "octagon_half":
		var fp := octagon_footprint(layout, gx)
		var c := CellTypes.octagon_chamfer(fp)
		var aw := fp - 2 * c
		var keys := ["east", "ne", "north", "nw", "west", "sw", "south", "se", "cap"]
		var widths := [aw, c, aw, c, aw, c, aw, c, fp]
		var col := 0
		for i in range(9):
			var fw: int = widths[i]
			var fh: int = fp if i == 8 else image.get_height()
			faces[keys[i]] = image.get_region(Rect2i(col, 0, fw, fh))
			col += fw
	elif layout == "net":
		faces["top"] = image.get_region(Rect2i(0, 0, tw, th))
		faces["front"] = image.get_region(Rect2i(tw, 0, tw, th))
		faces["right"] = image.get_region(Rect2i(tw * 2, 0, tw, th))
		faces["bottom"] = image.get_region(Rect2i(0, th, tw, th))
		faces["back"] = image.get_region(Rect2i(tw, th, tw, th))
		faces["left"] = image.get_region(Rect2i(tw * 2, th, tw, th))
	elif layout == "capped":
		var sides := image.get_region(Rect2i(0, 0, tw, th))
		var cap := image.get_region(Rect2i(tw, 0, tw, th))
		faces = {"front": sides, "back": sides, "right": sides, "left": sides, "top": cap, "bottom": cap}
	else:  # uniform
		faces = {"front": image, "back": image, "right": image, "left": image, "top": image, "bottom": image}
	return faces

# ─── reverse: rebuild an atlas from the current cells ────────────────────────
# The Texture Editor derives its canvas from the live model (the voxels are the
# source of truth), so it can never desync from what's on screen.
#
# Rather than hand-write an inverse per shape, we invert the REAL importer: run a
# probe atlas whose every texel is a unique colour through build_cells, note
# which cell face each texel landed on, then read those faces from the actual
# cells. The importer is the single source of truth, so reconstruction can never
# drift from it, and it's exact wherever import is 1:1.

# Atlas pixel size for a layout (block mode: gx = gy = gz = 32).
static func atlas_dims(layout: String, gx: int, gy: int) -> Vector2i:
	match layout:
		"uniform": return Vector2i(gx, gy)
		"capped": return Vector2i(gx * 2, gy)
		"net": return Vector2i(gx * 3, gy * 2)
		"octagon_full": return Vector2i(CellTypes.octagon_atlas_width(gx), gy)
		"octagon_half": return Vector2i(CellTypes.octagon_atlas_width(gx / 2), gy)
		"ramp": return Vector2i(128, 64)
		"gable": return Vector2i(128, 48)
		"diagwall": return Vector2i(112, 32)
		"diamond": return Vector2i(96, 32)
		"chamfered": return Vector2i(144, 32)
		"cross": return Vector2i(160, 32)
		"pipe_quarter": return Vector2i(120, 32)
		"stairs_2": return Vector2i(128, 32)
		"stairs_4": return Vector2i(80, 64)
		"panel": return Vector2i(64, 34)
		"slab_quarter": return Vector2i(64, 48)
		"slab_half": return Vector2i(64, 64)
	return Vector2i.ZERO

const _FACE_DIR := {
	CellTypes.FACE_TOP: Vector3i(0, 1, 0), CellTypes.FACE_BOTTOM: Vector3i(0, -1, 0),
	CellTypes.FACE_RIGHT: Vector3i(1, 0, 0), CellTypes.FACE_LEFT: Vector3i(-1, 0, 0),
	CellTypes.FACE_FRONT: Vector3i(0, 0, 1), CellTypes.FACE_BACK: Vector3i(0, 0, -1),
}
# Visibility rank: when several faces share an atlas texel, the most-seen one
# wins. Top is seen most, bottom least — so a shared cap texel takes the top
# color and the bottom conforms.
const _FACE_VIS := {
	CellTypes.FACE_TOP: 6, CellTypes.FACE_RIGHT: 3, CellTypes.FACE_LEFT: 3,
	CellTypes.FACE_FRONT: 3, CellTypes.FACE_BACK: 3, CellTypes.FACE_BOTTOM: 1,
}

static func reconstruct_atlas(layout: String, cells: Array, gx: int, gy: int, gz: int) -> Image:
	var dims := atlas_dims(layout, gx, gy)
	if dims == Vector2i.ZERO:
		return null
	var w := dims.x
	var h := dims.y
	if w * h >= 0x10000:      # codes must fit in a distinct RGB565 value (none do)
		return null
	# Probe: each texel a unique code 1..w*h, as a colour that re-encodes to it.
	var probe := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	for v in range(h):
		for u in range(w):
			probe.set_pixel(u, v, CellTypes.decode_rgb565(1 + v * w + u))
	var probe_cells: Array = build_cells(layout, probe, gx, gy, gz, default_opt(layout))
	# Inverse map: code -> the cell face that read it. When several faces share a
	# texel, keep the most-visible: exposed beats interior, then top > sides >
	# bottom (rank = exposed*100 + face visibility).
	var src := {}   # code -> [x, y, z, slot, rank]
	for x in range(gx):
		for y in range(gy):
			for z in range(gz):
				var pc: Array = probe_cells[x][y][z]
				if pc[0] == CellTypes.Type.EMPTY:
					continue
				for slot in range(CellTypes.FACE_TOP, CellTypes.FACE_BACK + 1):
					var code: int = pc[slot]
					if code <= 0 or code > w * h:
						continue
					var d: Vector3i = _FACE_DIR[slot]
					var nx := x + d.x; var ny := y + d.y; var nz := z + d.z
					var exposed: bool = nx < 0 or nx >= gx or ny < 0 or ny >= gy or nz < 0 or nz >= gz \
						or probe_cells[nx][ny][nz][0] == CellTypes.Type.EMPTY
					var rank: int = (100 if exposed else 0) + _FACE_VIS[slot]
					var cur = src.get(code)
					if cur == null or rank > cur[4]:
						src[code] = [x, y, z, slot, rank]
	var out := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	out.fill(Color(0, 0, 0, 0))
	for code in src:
		var e: Array = src[code]
		if cells[e[0]][e[1]][e[2]][0] == CellTypes.Type.EMPTY:
			continue
		out.set_pixel((code - 1) % w, (code - 1) / w, CellTypes.decode_color(cells[e[0]][e[1]][e[2]][e[3]]))
	return out

# How many EXPOSED faces of `cells` this atlas can't reproduce — i.e. per-face
# voxel edits that exceed what the shared-texel atlas can hold (a chamfer top
# painted differently from its bottom, etc.). 0 means the atlas is a faithful
# round-trip. Used to warn instead of silently showing a stale texture.
static func atlas_divergence(layout: String, cells: Array, atlas: Image, gx: int, gy: int, gz: int) -> int:
	if atlas == null:
		return 0
	var rebuilt: Array = build_cells(layout, atlas, gx, gy, gz, default_opt(layout))
	var n := 0
	for x in range(gx):
		for y in range(gy):
			for z in range(gz):
				var rc: Array = cells[x][y][z]
				if rc[0] == CellTypes.Type.EMPTY:
					continue
				for slot in range(CellTypes.FACE_TOP, CellTypes.FACE_BACK + 1):
					var d: Vector3i = _FACE_DIR[slot]
					var nx := x + d.x; var ny := y + d.y; var nz := z + d.z
					var exposed: bool = nx < 0 or nx >= gx or ny < 0 or ny >= gy or nz < 0 or nz >= gz \
						or cells[nx][ny][nz][0] == CellTypes.Type.EMPTY
					if exposed and rebuilt[x][y][z][slot] != rc[slot]:
						n += 1
	return n

# One 32x32 face image, reading the exact cell face slot build_cube writes to.
static func _face_img(cells: Array, face: String, gx: int, gy: int, gz: int) -> Image:
	var img := Image.create_empty(gx, gy, false, Image.FORMAT_RGBA8)
	for u in range(gx):
		for v in range(gy):
			var p: Vector3i
			var slot: int
			match face:
				"front": p = Vector3i(u, gy - 1 - v, gz - 1); slot = CellTypes.FACE_FRONT
				"back": p = Vector3i(gx - 1 - u, gy - 1 - v, 0); slot = CellTypes.FACE_BACK
				"right": p = Vector3i(gx - 1, gy - 1 - v, gz - 1 - u); slot = CellTypes.FACE_RIGHT
				"left": p = Vector3i(0, gy - 1 - v, u); slot = CellTypes.FACE_LEFT
				"top": p = Vector3i(u, gy - 1, v); slot = CellTypes.FACE_TOP
				_: p = Vector3i(u, 0, gz - 1 - v); slot = CellTypes.FACE_BOTTOM
			var cell: Array = cells[p.x][p.y][p.z]
			if cell[0] == CellTypes.Type.EMPTY:
				img.set_pixel(u, v, Color(0, 0, 0, 0))
			else:
				img.set_pixel(u, v, CellTypes.decode_color(cell[slot]))
	return img

# Best-effort layout guess from geometry when the model carries no stored shape.
# A full-ish solid block reconstructs as a cube: "uniform" if all six faces are
# identical, else "net" (which can hold any per-face colouring). "" if there is
# nothing to show.
static func guess_layout(cells: Array, gx: int, gy: int, gz: int) -> String:
	var any := false
	for x in range(gx):
		for y in range(gy):
			for z in range(gz):
				if cells[x][y][z][0] != CellTypes.Type.EMPTY:
					any = true
					break
			if any: break
		if any: break
	if not any:
		return ""
	var faces := ["front", "back", "right", "left", "top", "bottom"]
	var first := _face_img(cells, faces[0], gx, gy, gz).get_data()
	for i in range(1, faces.size()):
		if _face_img(cells, faces[i], gx, gy, gz).get_data() != first:
			return "net"
	return "uniform"

# ─── grid helper ─────────────────────────────────────────────────────────────
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

# ─── CUBE (uniform / capped / net) ───────────────────────────────────────────
static func build_cube(faces: Dictionary, use_alpha: bool, gx: int, gy: int, gz: int) -> Array:
	var cells := _new_cells(gx, gy, gz)
	var face_keys := ["top", "bottom", "right", "left", "front", "back"]
	var color_maps := {}
	var color_counts := {}
	for key in face_keys:
		var img: Image = faces[key]
		var cmap: Array = []
		cmap.resize(img.get_width())
		for u in range(img.get_width()):
			cmap[u] = []
			cmap[u].resize(img.get_height())
			for v in range(img.get_height()):
				var pixel := img.get_pixel(u, v)
				if not use_alpha and pixel.a < 0.5:
					cmap[u][v] = -1
				else:
					var encoded := CellTypes.encode_rgb5551(pixel) if use_alpha else CellTypes.encode_rgb565(pixel)
					cmap[u][v] = encoded
					color_counts[encoded] = color_counts.get(encoded, 0) + 1
		color_maps[key] = cmap

	var fill_color := 0
	var best_count := 0
	for idx in color_counts:
		if color_counts[idx] > best_count:
			best_count = color_counts[idx]
			fill_color = idx
	if use_alpha:
		var fc := CellTypes.decode_color(fill_color)
		fill_color = CellTypes.encode_rgb5551(Color(fc.r, fc.g, fc.b, 0.0))

	# Cutout textures are hollow (only a 1-voxel shell); opaque are fully solid.
	if use_alpha:
		for x in range(gx):
			for y in range(gy):
				for z in range(gz):
					if x == 0 or x == gx - 1 or y == 0 or y == gy - 1 or z == 0 or z == gz - 1:
						cells[x][y][z] = CellTypes.make_cell(CellTypes.Type.SOLID, 0, fill_color)
	else:
		for x in range(gx):
			for y in range(gy):
				for z in range(gz):
					cells[x][y][z] = CellTypes.make_cell(CellTypes.Type.SOLID, 0, fill_color)

	_apply_face_texture(cells, color_maps["front"], CellTypes.FACE_FRONT,
		func(u, v): return Vector3i(u, gy - 1 - v, gz - 1),
		func(u, v): return Vector3i(u, gy - 1 - v, gz - 1))
	_apply_face_texture(cells, color_maps["back"], CellTypes.FACE_BACK,
		func(u, v): return Vector3i(gx - 1 - u, gy - 1 - v, 0),
		func(u, v): return Vector3i(gx - 1 - u, gy - 1 - v, 0))
	_apply_face_texture(cells, color_maps["right"], CellTypes.FACE_RIGHT,
		func(u, v): return Vector3i(gx - 1, gy - 1 - v, gz - 1 - u),
		func(u, v): return Vector3i(gx - 1, gy - 1 - v, gz - 1 - u))
	_apply_face_texture(cells, color_maps["left"], CellTypes.FACE_LEFT,
		func(u, v): return Vector3i(0, gy - 1 - v, u),
		func(u, v): return Vector3i(0, gy - 1 - v, u))
	_apply_face_texture(cells, color_maps["top"], CellTypes.FACE_TOP,
		func(u, v): return Vector3i(u, gy - 1, v),
		func(u, v): return Vector3i(u, gy - 1, v))
	_apply_face_texture(cells, color_maps["bottom"], CellTypes.FACE_BOTTOM,
		func(u, v): return Vector3i(u, 0, gz - 1 - v),
		func(u, v): return Vector3i(u, 0, gz - 1 - v))

	if use_alpha:
		_erase_transparent(cells, gx, gy, gz)
	return cells

static func _apply_face_texture(cells: Array, color_map: Array, face_idx: int, erase_pos: Callable, color_pos: Callable) -> void:
	var w: int = color_map.size()
	var h: int = color_map[0].size()
	for u in range(w):
		for v in range(h):
			var ci: int = color_map[u][v]
			if ci == -1:
				var p: Vector3i = erase_pos.call(u, v)
				cells[p.x][p.y][p.z] = CellTypes.empty_cell()
			else:
				var p: Vector3i = color_pos.call(u, v)
				cells[p.x][p.y][p.z][face_idx] = ci

# ─── OCTAGON (full / half) ───────────────────────────────────────────────────
static func build_octagon(faces: Dictionary, footprint: int, gx: int, gy: int, gz: int, use_alpha: bool) -> Array:
	var cells := _new_cells(gx, gy, gz)
	var c := CellTypes.octagon_chamfer(footprint)
	var ox := (gx - footprint) / 2
	var oz := (gz - footprint) / 2

	var oct_keys := ["east", "ne", "north", "nw", "west", "sw", "south", "se", "cap"]
	var color_maps := {}
	for key in oct_keys:
		var img: Image = faces[key]
		var cmap: Array = []
		cmap.resize(img.get_width())
		for u in range(img.get_width()):
			cmap[u] = []
			cmap[u].resize(img.get_height())
			for v in range(img.get_height()):
				var pixel := img.get_pixel(u, v)
				cmap[u][v] = CellTypes.encode_rgb5551(pixel) if use_alpha else CellTypes.encode_rgb565(pixel)
		color_maps[key] = cmap

	var cap_map: Array = color_maps["cap"]
	var cap_counts := {}
	for u in range(cap_map.size()):
		for v in range(cap_map[u].size()):
			var cv: int = cap_map[u][v]
			cap_counts[cv] = cap_counts.get(cv, 0) + 1
	var fill_color := 0
	var best_count := 0
	for idx in cap_counts:
		if cap_counts[idx] > best_count:
			best_count = cap_counts[idx]
			fill_color = idx
	if use_alpha:
		var fc := CellTypes.decode_color(fill_color)
		fill_color = CellTypes.encode_rgb5551(Color(fc.r, fc.g, fc.b, 0.0))

	var fp := footprint
	for lx in range(fp):
		for y in range(gy):
			for lz in range(fp):
				var x := ox + lx
				var z := oz + lz
				var in_octagon := true
				var corner_type := -1
				if lx + lz < c:
					in_octagon = false
					if lx + lz == c - 1: corner_type = 0
				elif (fp - 1 - lx) + lz < c:
					in_octagon = false
					if (fp - 1 - lx) + lz == c - 1: corner_type = 1
				elif (fp - 1 - lx) + (fp - 1 - lz) < c:
					in_octagon = false
					if (fp - 1 - lx) + (fp - 1 - lz) == c - 1: corner_type = 2
				elif lx + (fp - 1 - lz) < c:
					in_octagon = false
					if lx + (fp - 1 - lz) == c - 1: corner_type = 3
				if not in_octagon:
					if corner_type >= 0:
						var orientation: int
						match corner_type:
							0: orientation = 2
							1: orientation = 3
							2: orientation = 0
							_: orientation = 1
						cells[x][y][z] = CellTypes.make_cell(CellTypes.Type.PRISM, orientation, fill_color)
				else:
					cells[x][y][z] = CellTypes.make_cell(CellTypes.Type.SOLID, 0, fill_color)

	var x_max := ox + fp - 1
	var z_max := oz + fp - 1
	_apply_octagon_side(cells, color_maps["east"], gy,
		func(i, v): return Vector3i(x_max, gy - 1 - v, oz + c + i), CellTypes.FACE_RIGHT)
	_apply_octagon_side(cells, color_maps["west"], gy,
		func(i, v): return Vector3i(ox, gy - 1 - v, z_max - c - i), CellTypes.FACE_LEFT)
	_apply_octagon_side(cells, color_maps["north"], gy,
		func(i, v): return Vector3i(x_max - c - i, gy - 1 - v, z_max), CellTypes.FACE_FRONT)
	_apply_octagon_side(cells, color_maps["south"], gy,
		func(i, v): return Vector3i(ox + c + i, gy - 1 - v, oz), CellTypes.FACE_BACK)

	_apply_octagon_diag_color(cells, color_maps["ne"], gy, c, 2, ox, oz, fp)
	_apply_octagon_diag_color(cells, color_maps["nw"], gy, c, 3, ox, oz, fp)
	_apply_octagon_diag_color(cells, color_maps["sw"], gy, c, 0, ox, oz, fp)
	_apply_octagon_diag_color(cells, color_maps["se"], gy, c, 1, ox, oz, fp)

	# caps — corner prisms included: their top/bottom triangles show the cap
	# design (same indexing as the neighboring solids), lateral slots keep the
	# diagonal-strip sample.
	for lx in range(fp):
		for lz in range(fp):
			var x := ox + lx
			var z := oz + lz
			if cells[x][0][z][0] != CellTypes.Type.EMPTY:
				cells[x][0][z][CellTypes.FACE_BOTTOM] = cap_map[lx][fp - 1 - lz]
			if cells[x][gy - 1][z][0] != CellTypes.Type.EMPTY:
				cells[x][gy - 1][z][CellTypes.FACE_TOP] = cap_map[lx][lz]

	if use_alpha:
		_erase_transparent(cells, gx, gy, gz)
	return cells

static func _apply_octagon_side(cells: Array, color_map: Array, gy: int, pos_fn: Callable, face_idx: int) -> void:
	var face_w: int = color_map.size()
	for i in range(face_w):
		for v in range(gy):
			var ci: int = color_map[i][v]
			var p: Vector3i = pos_fn.call(i, v)
			cells[p.x][p.y][p.z][face_idx] = ci

static func _apply_octagon_diag_color(cells: Array, color_map: Array, gy: int, chamfer: int, corner_type: int, ox: int, oz: int, fp: int) -> void:
	var prism_positions: Array = []
	for lx in range(fp):
		for lz in range(fp):
			var on_edge := false
			match corner_type:
				0: on_edge = (lx + lz == chamfer - 1)
				1: on_edge = ((fp - 1 - lx) + lz == chamfer - 1)
				2: on_edge = ((fp - 1 - lx) + (fp - 1 - lz) == chamfer - 1)
				3: on_edge = (lx + (fp - 1 - lz) == chamfer - 1)
			if on_edge:
				prism_positions.append(Vector2i(ox + lx, oz + lz))
	match corner_type:
		0: prism_positions.sort_custom(func(a, b): return a.x < b.x)
		1: prism_positions.sort_custom(func(a, b): return a.x > b.x)
		2: prism_positions.sort_custom(func(a, b): return a.x > b.x)
		3: prism_positions.sort_custom(func(a, b): return a.x < b.x)
	for idx in range(prism_positions.size()):
		var pos: Vector2i = prism_positions[idx]
		for y in range(gy):
			var ci: int = color_map[idx][gy - 1 - y]
			# Diagonal-strip sample on every slot; the caps loop afterwards
			# overwrites FACE_TOP / FACE_BOTTOM on the end layers with the cap.
			var pc: Array = cells[pos.x][y][pos.y]
			for fi in range(CellTypes.FACE_TOP, CellTypes.FACE_BACK + 1):
				pc[fi] = ci

# ─── shared ──────────────────────────────────────────────────────────────────
static func _erase_transparent(cells: Array, gx: int, gy: int, gz: int) -> void:
	for x in range(gx):
		for y in range(gy):
			for z in range(gz):
				var cell: Array = cells[x][y][z]
				if cell[0] == CellTypes.Type.EMPTY:
					continue
				var all_t := true
				for fi in range(CellTypes.FACE_TOP, CellTypes.FACE_BACK + 1):
					var cv: int = cell[fi]
					if not CellTypes.is_rgb5551(cv) or CellTypes.decode_rgb5551(cv).a >= CellTypes.ALPHA_THRESHOLD:
						all_t = false
						break
				if all_t:
					cells[x][y][z] = CellTypes.empty_cell()
