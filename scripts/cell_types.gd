class_name CellTypes

enum Type {
	EMPTY = 0,
	SOLID = 1,
	PRISM = 2,
}

const PALETTE = [
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

const PALETTE_NAMES = [
	"Green", "Brown", "Gray", "Skin", "Skin Shadow", "Dark Green",
	"White", "Red", "Black", "Pink", "Blonde", "Blue",
	"Dark Brown", "Skin Light", "Tan", "Auburn",
]

static func get_orientation_name(orientation: int) -> String:
	var axis_names := ["Y", "X", "Z"]
	var corner_names := ["SW", "SE", "NE", "NW"]
	return axis_names[orientation / 4] + "-" + corner_names[orientation % 4]
