class_name CellTypes

enum Type {
	EMPTY = 0,
	SOLID = 1,
	PRISM = 2,
}

const _BASE_PALETTE = [
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

const _BASE_NAMES = [
	"Green", "Brown", "Gray", "Skin", "Skin Shadow", "Dark Green",
	"White", "Red", "Black", "Pink", "Blonde", "Blue",
	"Dark Brown", "Skin Light", "Tan", "Auburn",
]

static var PALETTE: Array = []
static var PALETTE_NAMES: Array = []

static func _static_init() -> void:
	PALETTE = _BASE_PALETTE.duplicate()
	PALETTE_NAMES = _BASE_NAMES.duplicate()

	# 24 pure grays (indices 16-39)
	for i in range(24):
		var v := (i + 1) / 25.0
		PALETTE.append(Color(v, v, v))
		PALETTE_NAMES.append("Gray_%02d" % (i + 16))

	# 12 hues x 3 saturations x 3 values = 108 chromatic (indices 40-147)
	var hues := [0.0, 30.0, 60.0, 90.0, 120.0, 150.0, 180.0, 210.0, 240.0, 270.0, 300.0, 330.0]
	var sats := [0.4, 0.7, 1.0]
	var vals := [0.4, 0.7, 1.0]
	for h in hues:
		for s in sats:
			for v in vals:
				PALETTE.append(Color.from_hsv(h / 360.0, s, v))
				PALETTE_NAMES.append("H%03dS%02dV%02d" % [int(h), int(s * 100), int(v * 100)])

	# 18 hues x 2 sat x 2 val = 72 more mid-tones (indices 148-219)
	var hues2 := [15.0, 45.0, 75.0, 105.0, 135.0, 165.0, 195.0, 225.0, 255.0, 285.0, 315.0, 345.0,
				  10.0, 50.0, 100.0, 160.0, 200.0, 280.0]
	var sats2 := [0.55, 0.85]
	var vals2 := [0.55, 0.85]
	for h in hues2:
		for s in sats2:
			for v in vals2:
				PALETTE.append(Color.from_hsv(h / 360.0, s, v))
				PALETTE_NAMES.append("H%03dS%02dV%02d" % [int(h), int(s * 100), int(v * 100)])

	# 12 pastels (indices 220-231)
	for i in range(12):
		var h := i / 12.0
		PALETTE.append(Color.from_hsv(h, 0.25, 0.95))
		PALETTE_NAMES.append("Pastel_%02d" % i)

	# 12 deep/dark shades (indices 232-243)
	for i in range(12):
		var h := i / 12.0
		PALETTE.append(Color.from_hsv(h, 0.9, 0.25))
		PALETTE_NAMES.append("Deep_%02d" % i)

	# 12 warm/earth fill (indices 244-255)
	var earth := [
		Color(0.72, 0.45, 0.20), Color(0.60, 0.35, 0.15), Color(0.85, 0.60, 0.35),
		Color(0.50, 0.30, 0.12), Color(0.78, 0.55, 0.30), Color(0.65, 0.42, 0.22),
		Color(0.90, 0.70, 0.45), Color(0.45, 0.25, 0.10), Color(0.82, 0.65, 0.40),
		Color(0.55, 0.32, 0.18), Color(0.70, 0.48, 0.28), Color(0.88, 0.75, 0.55),
	]
	for i in range(earth.size()):
		PALETTE.append(earth[i])
		PALETTE_NAMES.append("Earth_%02d" % i)

static func get_orientation_name(orientation: int) -> String:
	var axis_names := ["Y", "X", "Z"]
	var corner_names := ["SW", "SE", "NE", "NW"]
	return axis_names[orientation / 4] + "-" + corner_names[orientation % 4]
