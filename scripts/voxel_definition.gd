class_name VoxelDefinition
extends Resource

@export var grid_x: int = 16
@export var grid_y: int = 16
@export var grid_z: int = 16
@export var edit_mode: int = 0
@export var cell_data: PackedInt32Array = PackedInt32Array()

func set_from_cells(p_cells: Array, gx: int, gy: int, gz: int, mode: int) -> void:
	grid_x = gx
	grid_y = gy
	grid_z = gz
	edit_mode = mode
	cell_data.resize(gx * gy * gz * 3)
	for x in range(gx):
		for y in range(gy):
			for z in range(gz):
				var idx := (x * gy * gz + y * gz + z) * 3
				var cell: Array = p_cells[x][y][z]
				cell_data[idx] = cell[0]
				cell_data[idx + 1] = cell[1]
				cell_data[idx + 2] = cell[2]

func to_cells() -> Array:
	var p_cells := []
	p_cells.resize(grid_x)
	for x in range(grid_x):
		p_cells[x] = []
		p_cells[x].resize(grid_y)
		for y in range(grid_y):
			p_cells[x][y] = []
			p_cells[x][y].resize(grid_z)
			for z in range(grid_z):
				var idx := (x * grid_y * grid_z + y * grid_z + z) * 3
				if idx + 2 < cell_data.size():
					p_cells[x][y][z] = [cell_data[idx], cell_data[idx + 1], cell_data[idx + 2]]
				else:
					p_cells[x][y][z] = [CellTypes.Type.EMPTY, 0, 0]
	return p_cells

static func _fill_box(p_cells: Array, x0: int, y0: int, z0: int, x1: int, y1: int, z1: int, cell_type: int, orientation: int, color_idx: int) -> void:
	for x in range(x0, x1 + 1):
		for y in range(y0, y1 + 1):
			for z in range(z0, z1 + 1):
				p_cells[x][y][z] = [cell_type, orientation, color_idx]

static func _make_empty_cells(gx: int, gy: int, gz: int) -> Array:
	var p_cells := []
	p_cells.resize(gx)
	for x in range(gx):
		p_cells[x] = []
		p_cells[x].resize(gy)
		for y in range(gy):
			p_cells[x][y] = []
			p_cells[x][y].resize(gz)
			for z in range(gz):
				p_cells[x][y][z] = [CellTypes.Type.EMPTY, 0, 0]
	return p_cells

static func create_male() -> VoxelDefinition:
	var def := VoxelDefinition.new()
	var c := _make_empty_cells(32, 64, 32)
	var S := CellTypes.Type.SOLID

	# Palette: 0=Green, 1=Brown, 2=Gray, 3=Sand, 4=Wood, 5=DkGreen, 6=LtGray, 7=Red
	var SKIN := 3
	var SHIRT := 2
	var PANTS := 1
	var SHOES := 4
	var HAIR := 1

	# Feet (y 0-5)
	_fill_box(c, 10, 0, 12, 15, 5, 19, S, 0, SHOES)
	_fill_box(c, 16, 0, 12, 21, 5, 19, S, 0, SHOES)

	# Legs (y 6-29)
	_fill_box(c, 10, 6, 12, 15, 29, 19, S, 0, PANTS)
	_fill_box(c, 16, 6, 12, 21, 29, 19, S, 0, PANTS)

	# Torso (y 30-49)
	_fill_box(c, 8, 30, 10, 23, 49, 21, S, 0, SHIRT)

	# Arms (y 30-49, hanging at sides)
	_fill_box(c, 4, 30, 12, 7, 49, 19, S, 0, SHIRT)
	_fill_box(c, 24, 30, 12, 27, 49, 19, S, 0, SHIRT)

	# Hands (y 26-29)
	_fill_box(c, 4, 26, 12, 7, 29, 19, S, 0, SKIN)
	_fill_box(c, 24, 26, 12, 27, 29, 19, S, 0, SKIN)

	# Neck (y 50-51)
	_fill_box(c, 12, 50, 12, 19, 51, 19, S, 0, SKIN)

	# Head (y 52-63)
	_fill_box(c, 10, 52, 10, 21, 63, 21, S, 0, SKIN)

	# Hair (top and back of head)
	_fill_box(c, 10, 60, 10, 21, 63, 21, S, 0, HAIR)
	_fill_box(c, 10, 56, 10, 21, 63, 11, S, 0, HAIR)

	# Eyes (2x2 each on front face)
	_fill_box(c, 12, 58, 21, 13, 59, 21, S, 0, 6)
	_fill_box(c, 18, 58, 21, 19, 59, 21, S, 0, 6)

	# Mouth
	_fill_box(c, 14, 55, 21, 17, 55, 21, S, 0, 7)

	def.set_from_cells(c, 32, 64, 32, 1)
	return def

static func create_female() -> VoxelDefinition:
	var def := VoxelDefinition.new()
	var c := _make_empty_cells(32, 64, 32)
	var S := CellTypes.Type.SOLID

	var SKIN := 3
	var TOP := 7
	var SKIRT := 5
	var SHOES := 4
	var HAIR := 1
	var LEGS_COL := 6

	# Feet (y 0-5)
	_fill_box(c, 10, 0, 12, 15, 5, 19, S, 0, SHOES)
	_fill_box(c, 16, 0, 12, 21, 5, 19, S, 0, SHOES)

	# Legs (y 6-25)
	_fill_box(c, 10, 6, 12, 15, 25, 19, S, 0, LEGS_COL)
	_fill_box(c, 16, 6, 12, 21, 25, 19, S, 0, LEGS_COL)

	# Skirt/hips (y 26-35, wider)
	_fill_box(c, 8, 26, 10, 23, 35, 21, S, 0, SKIRT)

	# Torso (y 36-49, narrower)
	_fill_box(c, 10, 36, 10, 21, 49, 21, S, 0, TOP)

	# Arms (y 32-49)
	_fill_box(c, 6, 32, 12, 9, 49, 19, S, 0, TOP)
	_fill_box(c, 22, 32, 12, 25, 49, 19, S, 0, TOP)

	# Lower arms / skin (y 28-31)
	_fill_box(c, 6, 28, 12, 9, 31, 19, S, 0, SKIN)
	_fill_box(c, 22, 28, 12, 25, 31, 19, S, 0, SKIN)

	# Neck (y 50-51)
	_fill_box(c, 12, 50, 12, 19, 51, 19, S, 0, SKIN)

	# Head (y 52-63)
	_fill_box(c, 10, 52, 10, 21, 63, 21, S, 0, SKIN)

	# Hair (longer, covering top, back, and sides)
	_fill_box(c, 10, 58, 10, 21, 63, 21, S, 0, HAIR)
	_fill_box(c, 10, 52, 10, 21, 63, 11, S, 0, HAIR)
	_fill_box(c, 10, 52, 10, 11, 63, 21, S, 0, HAIR)
	_fill_box(c, 20, 52, 10, 21, 63, 21, S, 0, HAIR)
	# Hair hanging below head
	_fill_box(c, 10, 46, 10, 11, 51, 13, S, 0, HAIR)
	_fill_box(c, 20, 46, 10, 21, 51, 13, S, 0, HAIR)

	# Eyes (2x2 each)
	_fill_box(c, 12, 58, 21, 13, 59, 21, S, 0, 6)
	_fill_box(c, 18, 58, 21, 19, 59, 21, S, 0, 6)

	# Mouth
	_fill_box(c, 14, 55, 21, 17, 55, 21, S, 0, 7)

	def.set_from_cells(c, 32, 64, 32, 1)
	return def
