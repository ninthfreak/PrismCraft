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
	var c := _make_empty_cells(16, 32, 16)
	var S := CellTypes.Type.SOLID

	# Palette: 0=Green, 1=Brown, 2=Gray, 3=Sand, 4=Wood, 5=DkGreen, 6=LtGray, 7=Red
	var SKIN := 3
	var SHIRT := 2
	var PANTS := 1
	var SHOES := 4
	var HAIR := 1

	# Feet (y 0-2)
	_fill_box(c, 5, 0, 6, 7, 2, 9, S, 0, SHOES)
	_fill_box(c, 8, 0, 6, 10, 2, 9, S, 0, SHOES)

	# Legs (y 3-14)
	_fill_box(c, 5, 3, 6, 7, 14, 9, S, 0, PANTS)
	_fill_box(c, 8, 3, 6, 10, 14, 9, S, 0, PANTS)

	# Torso (y 15-24)
	_fill_box(c, 4, 15, 5, 11, 24, 10, S, 0, SHIRT)

	# Arms (y 15-24, hanging at sides)
	_fill_box(c, 2, 15, 6, 3, 24, 9, S, 0, SHIRT)
	_fill_box(c, 12, 15, 6, 13, 24, 9, S, 0, SHIRT)

	# Hands (y 13-14)
	_fill_box(c, 2, 13, 6, 3, 14, 9, S, 0, SKIN)
	_fill_box(c, 12, 13, 6, 13, 14, 9, S, 0, SKIN)

	# Neck (y 25)
	_fill_box(c, 6, 25, 6, 9, 25, 9, S, 0, SKIN)

	# Head (y 26-31)
	_fill_box(c, 5, 26, 5, 10, 31, 10, S, 0, SKIN)

	# Hair (top and back of head)
	_fill_box(c, 5, 30, 5, 10, 31, 10, S, 0, HAIR)
	_fill_box(c, 5, 28, 5, 10, 31, 5, S, 0, HAIR)

	# Eyes (overwrite two cells on front face)
	c[6][29][10] = [S, 0, 6]
	c[9][29][10] = [S, 0, 6]

	def.set_from_cells(c, 16, 32, 16, 1)
	return def

static func create_female() -> VoxelDefinition:
	var def := VoxelDefinition.new()
	var c := _make_empty_cells(16, 32, 16)
	var S := CellTypes.Type.SOLID

	var SKIN := 3
	var TOP := 7
	var SKIRT := 5
	var SHOES := 4
	var HAIR := 1
	var LEGS_COL := 6

	# Feet (y 0-2)
	_fill_box(c, 5, 0, 6, 7, 2, 9, S, 0, SHOES)
	_fill_box(c, 8, 0, 6, 10, 2, 9, S, 0, SHOES)

	# Legs (y 3-12)
	_fill_box(c, 5, 3, 6, 7, 12, 9, S, 0, LEGS_COL)
	_fill_box(c, 8, 3, 6, 10, 12, 9, S, 0, LEGS_COL)

	# Skirt/hips (y 13-17, wider)
	_fill_box(c, 4, 13, 5, 11, 17, 10, S, 0, SKIRT)

	# Torso (y 18-24, narrower)
	_fill_box(c, 5, 18, 5, 10, 24, 10, S, 0, TOP)

	# Arms (y 16-24)
	_fill_box(c, 3, 16, 6, 4, 24, 9, S, 0, TOP)
	_fill_box(c, 11, 16, 6, 12, 24, 9, S, 0, TOP)

	# Lower arms / skin (y 14-15)
	_fill_box(c, 3, 14, 6, 4, 15, 9, S, 0, SKIN)
	_fill_box(c, 11, 14, 6, 12, 15, 9, S, 0, SKIN)

	# Neck (y 25)
	_fill_box(c, 6, 25, 6, 9, 25, 9, S, 0, SKIN)

	# Head (y 26-31)
	_fill_box(c, 5, 26, 5, 10, 31, 10, S, 0, SKIN)

	# Hair (longer, covering top, back, and sides partway down)
	_fill_box(c, 5, 29, 5, 10, 31, 10, S, 0, HAIR)
	_fill_box(c, 5, 26, 5, 10, 31, 5, S, 0, HAIR)
	_fill_box(c, 5, 26, 5, 5, 31, 10, S, 0, HAIR)
	_fill_box(c, 10, 26, 5, 10, 31, 10, S, 0, HAIR)
	# Hair hanging below head
	_fill_box(c, 5, 23, 5, 5, 25, 6, S, 0, HAIR)
	_fill_box(c, 10, 23, 5, 10, 25, 6, S, 0, HAIR)

	# Eyes
	c[6][29][10] = [S, 0, 6]
	c[9][29][10] = [S, 0, 6]

	def.set_from_cells(c, 16, 32, 16, 1)
	return def
