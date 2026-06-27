class_name BlockTypes

enum Type {
	AIR = 0,
	GRASS,
	DIRT,
	STONE,
	SAND,
	WOOD,
	LEAVES,
}

static func get_color(block_type: int, face: String) -> Color:
	match block_type:
		Type.GRASS:
			if face == "top": return Color(0.36, 0.63, 0.21)
			return Color(0.45, 0.32, 0.18)
		Type.DIRT:
			if face == "top": return Color(0.55, 0.38, 0.22)
			if face == "side": return Color(0.50, 0.35, 0.20)
			return Color(0.45, 0.32, 0.18)
		Type.STONE:
			if face == "top": return Color(0.58, 0.58, 0.58)
			if face == "side": return Color(0.52, 0.52, 0.52)
			return Color(0.46, 0.46, 0.46)
		Type.SAND:
			if face == "top": return Color(0.86, 0.82, 0.62)
			if face == "side": return Color(0.80, 0.76, 0.56)
			return Color(0.74, 0.70, 0.50)
		Type.WOOD:
			if face == "top": return Color(0.60, 0.40, 0.20)
			if face == "side": return Color(0.55, 0.35, 0.18)
			return Color(0.50, 0.30, 0.15)
		Type.LEAVES:
			if face == "top": return Color(0.22, 0.52, 0.18)
			if face == "side": return Color(0.18, 0.45, 0.14)
			return Color(0.15, 0.40, 0.10)
	return Color.MAGENTA

static func get_name(block_type: int) -> String:
	match block_type:
		Type.GRASS: return "Grass"
		Type.DIRT: return "Dirt"
		Type.STONE: return "Stone"
		Type.SAND: return "Sand"
		Type.WOOD: return "Wood"
		Type.LEAVES: return "Leaves"
	return "Unknown"
