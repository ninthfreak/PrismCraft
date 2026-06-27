class_name CellTypes

enum Type {
	EMPTY = 0,
	SOLID = 1,
	PRISM = 2,
}

const PALETTE = [
	Color(0.36, 0.63, 0.21),  # Green
	Color(0.55, 0.38, 0.22),  # Brown
	Color(0.58, 0.58, 0.58),  # Gray
	Color(0.86, 0.82, 0.62),  # Sand
	Color(0.60, 0.40, 0.20),  # Wood
	Color(0.22, 0.52, 0.18),  # Dark Green
	Color(0.85, 0.85, 0.85),  # Light Gray
	Color(0.75, 0.30, 0.30),  # Red
]

const PALETTE_NAMES = [
	"Green", "Brown", "Gray", "Sand", "Wood", "Dark Green", "Light Gray", "Red"
]

static func get_orientation_name(orientation: int) -> String:
	var axis_names := ["Y", "X", "Z"]
	var corner_names := ["SW", "SE", "NE", "NW"]
	return axis_names[orientation / 4] + "-" + corner_names[orientation % 4]
