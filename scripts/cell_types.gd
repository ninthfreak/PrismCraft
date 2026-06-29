class_name CellTypes

enum Type {
	EMPTY = 0,
	SOLID = 1,
	PRISM = 2,
}

const FAVORITES = [
	Color(0.36, 0.63, 0.21),  # 0  Green
	Color(0.55, 0.38, 0.22),  # 1  Brown
	Color(0.58, 0.58, 0.58),  # 2  Gray
	Color(0.89, 0.73, 0.58),  # 3  Skin
	Color(0.72, 0.54, 0.40),  # 4  Skin Shadow
	Color(0.22, 0.52, 0.18),  # 5  Dark Green
	Color(0.93, 0.93, 0.93),  # 6  White
	Color(0.75, 0.30, 0.30),  # 7  Red
	Color(0.12, 0.10, 0.08),  # 8  Black
	Color(0.80, 0.52, 0.50),  # 9  Pink
	Color(0.86, 0.76, 0.42),  # 10 Blonde
	Color(0.28, 0.47, 0.75),  # 11 Blue
	Color(0.30, 0.18, 0.08),  # 12 Dark Brown
	Color(0.95, 0.82, 0.70),  # 13 Skin Light
	Color(0.80, 0.64, 0.48),  # 14 Tan
	Color(0.56, 0.20, 0.10),  # 15 Auburn
]

# ─── Color encoding ───
# RGB565 (opaque):  bits [15..11] R, [10..5] G, [4..0] B   — 65536 colors, no alpha
# RGB5551 (cutout): bits [15..11] R, [10..6] G, [5..1] B, [0] A  — 32768 colors + 1-bit alpha
# Stored values use bit 16 (RGB5551_FLAG) to distinguish format at decode time.
# Both formats fit in a 32-bit int alongside the flag.

const OCTAGON_CHAMFER := 9

static func octagon_chamfer(footprint: int) -> int:
	return roundi((2.0 - sqrt(2.0)) / 2.0 * footprint)

static func octagon_strip_width(footprint: int) -> int:
	var c := octagon_chamfer(footprint)
	var aw := footprint - 2 * c
	return 4 * aw + 4 * c

static func octagon_atlas_width(footprint: int) -> int:
	return octagon_strip_width(footprint) + footprint

static func validate_block_texture(w: int, h: int, grid_x: int, grid_y: int) -> String:
	if w == grid_x and h == grid_y:
		return "uniform"
	if w == grid_x * 2 and h == grid_y:
		return "column"
	if w == grid_x * 3 and h == grid_y * 2:
		return "net"
	if h == grid_y:
		var full_fp := grid_x
		if w == octagon_atlas_width(full_fp):
			return "octagon_full"
		var half_fp := grid_x / 2
		if w == octagon_atlas_width(half_fp):
			return "octagon_half"
	return ""

const RGB5551_FLAG := 0x10000
const ALPHA_THRESHOLD := 0.5  # import: alpha >= 0.5 → opaque (1); shader/discard: alpha < 0.5 → clip

static func encode_rgb565(c: Color) -> int:
	var r := clampi(int(c.r * 31.0 + 0.5), 0, 31)
	var g := clampi(int(c.g * 63.0 + 0.5), 0, 63)
	var b := clampi(int(c.b * 31.0 + 0.5), 0, 31)
	return (r << 11) | (g << 5) | b

static func decode_rgb565(v: int) -> Color:
	var r := ((v >> 11) & 0x1F) / 31.0
	var g := ((v >> 5) & 0x3F) / 63.0
	var b := (v & 0x1F) / 31.0
	return Color(r, g, b)

static func encode_rgb5551(c: Color) -> int:
	var r := clampi(int(c.r * 31.0 + 0.5), 0, 31)
	var g := clampi(int(c.g * 31.0 + 0.5), 0, 31)
	var b := clampi(int(c.b * 31.0 + 0.5), 0, 31)
	var a := 1 if c.a >= ALPHA_THRESHOLD else 0
	return ((r << 11) | (g << 6) | (b << 1) | a) | RGB5551_FLAG

static func decode_rgb5551(v: int) -> Color:
	var raw := v & 0xFFFF
	var r := ((raw >> 11) & 0x1F) / 31.0
	var g := ((raw >> 6) & 0x1F) / 31.0
	var b := ((raw >> 1) & 0x1F) / 31.0
	var a := float(raw & 1)
	return Color(r, g, b, a)

static func is_rgb5551(v: int) -> bool:
	return (v & RGB5551_FLAG) != 0

static func decode_color(v: int) -> Color:
	if (v & RGB5551_FLAG) != 0:
		return decode_rgb5551(v)
	return decode_rgb565(v)

static func color_name(v: int) -> String:
	var c := decode_color(v)
	return "C_%02X%02X%02X" % [int(c.r * 255), int(c.g * 255), int(c.b * 255)]

static func color_name_rgb565(v: int) -> String:
	var r := (v >> 11) & 0x1F
	var g := (v >> 5) & 0x3F
	var b := v & 0x1F
	return "C_%02X%02X%02X" % [r * 255 / 31, g * 255 / 63, b * 255 / 31]

static func image_has_alpha(image: Image) -> bool:
	for x in range(image.get_width()):
		for y in range(image.get_height()):
			if image.get_pixel(x, y).a < 1.0:
				return true
	return false

static func is_cutout_cell(cell: Array) -> bool:
	if cell[0] == Type.EMPTY:
		return false
	for fi in range(FACE_TOP, FACE_BACK + 1):
		if is_rgb5551(cell[fi]):
			return true
	return false

# Cell format: [type, orientation, c_top(+Y), c_bottom(-Y), c_right(+X), c_left(-X), c_front(+Z), c_back(-Z)]
# Face indices within cell array:
const FACE_TOP := 2     # +Y
const FACE_BOTTOM := 3  # -Y
const FACE_RIGHT := 4   # +X
const FACE_LEFT := 5    # -X
const FACE_FRONT := 6   # +Z
const FACE_BACK := 7    # -Z

static func make_cell(cell_type: int, orientation: int, color: int) -> Array:
	return [cell_type, orientation, color, color, color, color, color, color]

static func empty_cell() -> Array:
	return [Type.EMPTY, 0, 0, 0, 0, 0, 0, 0]

static func face_index_from_normal(normal: Vector3i) -> int:
	if normal.y > 0: return FACE_TOP
	if normal.y < 0: return FACE_BOTTOM
	if normal.x > 0: return FACE_RIGHT
	if normal.x < 0: return FACE_LEFT
	if normal.z > 0: return FACE_FRONT
	return FACE_BACK

static func get_orientation_name(orientation: int) -> String:
	var axis_names := ["Y", "X", "Z"]
	var corner_names := ["SW", "SE", "NE", "NW"]
	return axis_names[orientation / 4] + "-" + corner_names[orientation % 4]
