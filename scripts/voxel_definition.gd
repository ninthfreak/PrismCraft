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
	# ~1.75m tall = 56 cells, standing on y=4..y=59
	var def := VoxelDefinition.new()
	var c := _make_empty_cells(32, 64, 32)
	var S := CellTypes.Type.SOLID
	var SKIN := 3
	var HAIR := 1

	# Feet (y 4-6)
	_fill_box(c, 11, 4, 12, 15, 6, 20, S, 0, SKIN)
	_fill_box(c, 17, 4, 12, 21, 6, 20, S, 0, SKIN)

	# Lower legs (y 7-21)
	_fill_box(c, 12, 7, 13, 14, 21, 19, S, 0, SKIN)
	_fill_box(c, 18, 7, 13, 20, 21, 19, S, 0, SKIN)

	# Knees (y 20-22, slightly wider)
	_fill_box(c, 11, 20, 12, 15, 22, 20, S, 0, SKIN)
	_fill_box(c, 17, 20, 12, 21, 22, 20, S, 0, SKIN)

	# Thighs (y 23-32, thicker)
	_fill_box(c, 10, 23, 12, 15, 32, 20, S, 0, SKIN)
	_fill_box(c, 17, 23, 12, 22, 32, 20, S, 0, SKIN)

	# Pelvis/hips (y 31-34, connects legs)
	_fill_box(c, 10, 31, 11, 22, 34, 21, S, 0, SKIN)

	# Abdomen (y 35-39)
	_fill_box(c, 10, 35, 11, 22, 39, 21, S, 0, SKIN)

	# Chest (y 40-47, broader)
	_fill_box(c, 9, 40, 10, 23, 47, 22, S, 0, SKIN)

	# Nipples
	c[12][43][22] = [S, 0, 4]
	c[20][43][22] = [S, 0, 4]

	# Shoulders (y 46-48, widest point)
	_fill_box(c, 7, 46, 11, 9, 48, 21, S, 0, SKIN)
	_fill_box(c, 23, 46, 11, 25, 48, 21, S, 0, SKIN)

	# Upper arms (y 37-47)
	_fill_box(c, 5, 37, 12, 8, 47, 20, S, 0, SKIN)
	_fill_box(c, 24, 37, 12, 27, 47, 20, S, 0, SKIN)

	# Forearms (y 27-36)
	_fill_box(c, 5, 27, 13, 8, 36, 19, S, 0, SKIN)
	_fill_box(c, 24, 27, 13, 27, 36, 19, S, 0, SKIN)

	# Hands (y 24-26)
	_fill_box(c, 5, 24, 12, 8, 26, 19, S, 0, SKIN)
	_fill_box(c, 24, 24, 12, 27, 26, 19, S, 0, SKIN)

	# Neck (y 48-49)
	_fill_box(c, 13, 48, 13, 19, 49, 19, S, 0, SKIN)

	# Head (y 50-58)
	_fill_box(c, 11, 50, 11, 21, 58, 21, S, 0, SKIN)

	# Hair (short, top and back)
	_fill_box(c, 11, 56, 11, 21, 59, 21, S, 0, HAIR)
	_fill_box(c, 11, 52, 11, 21, 59, 12, S, 0, HAIR)

	# Eyes (2x2 on front face)
	_fill_box(c, 13, 55, 21, 14, 56, 21, S, 0, 6)
	_fill_box(c, 18, 55, 21, 19, 56, 21, S, 0, 6)

	# Nose
	c[16][54][ 22] = [S, 0, SKIN]

	# Mouth
	_fill_box(c, 14, 52, 21, 18, 52, 21, S, 0, 7)

	# Navel
	c[16][37][22] = [S, 0, 4]

	def.set_from_cells(c, 32, 64, 32, 1)
	return def

static func create_female() -> VoxelDefinition:
	# ~1.63m tall = 52 cells, standing on y=6..y=57
	var def := VoxelDefinition.new()
	var c := _make_empty_cells(32, 64, 32)
	var S := CellTypes.Type.SOLID
	var SKIN := 3
	var HAIR := 1

	# Feet (y 6-8)
	_fill_box(c, 12, 6, 12, 15, 8, 20, S, 0, SKIN)
	_fill_box(c, 17, 6, 12, 20, 8, 20, S, 0, SKIN)

	# Lower legs (y 9-21)
	_fill_box(c, 12, 9, 13, 15, 21, 19, S, 0, SKIN)
	_fill_box(c, 17, 9, 13, 20, 21, 19, S, 0, SKIN)

	# Knees (y 20-22)
	_fill_box(c, 12, 20, 12, 15, 22, 20, S, 0, SKIN)
	_fill_box(c, 17, 20, 12, 20, 22, 20, S, 0, SKIN)

	# Thighs (y 23-31, curvier)
	_fill_box(c, 10, 23, 12, 15, 31, 20, S, 0, SKIN)
	_fill_box(c, 17, 23, 12, 22, 31, 20, S, 0, SKIN)

	# Hips/pelvis (y 30-34, wider than male)
	_fill_box(c, 9, 30, 10, 23, 34, 22, S, 0, SKIN)

	# Waist (y 35-37, narrower)
	_fill_box(c, 11, 35, 11, 21, 37, 21, S, 0, SKIN)

	# Ribcage (y 38-41)
	_fill_box(c, 10, 38, 10, 22, 41, 22, S, 0, SKIN)

	# Chest/breasts (y 42-45)
	_fill_box(c, 10, 42, 10, 22, 45, 21, S, 0, SKIN)
	# Breast shape (protrudes forward)
	_fill_box(c, 12, 42, 21, 15, 44, 22, S, 0, SKIN)
	_fill_box(c, 17, 42, 21, 20, 44, 22, S, 0, SKIN)

	# Nipples
	c[13][43][23] = [S, 0, 4]
	c[19][43][23] = [S, 0, 4]

	# Shoulders (y 44-46, narrower than male)
	_fill_box(c, 8, 44, 12, 10, 46, 20, S, 0, SKIN)
	_fill_box(c, 22, 44, 12, 24, 46, 20, S, 0, SKIN)

	# Upper arms (y 36-45)
	_fill_box(c, 6, 36, 13, 9, 45, 19, S, 0, SKIN)
	_fill_box(c, 23, 36, 13, 26, 45, 19, S, 0, SKIN)

	# Forearms (y 27-35)
	_fill_box(c, 6, 27, 13, 9, 35, 19, S, 0, SKIN)
	_fill_box(c, 23, 27, 13, 26, 35, 19, S, 0, SKIN)

	# Hands (y 24-26)
	_fill_box(c, 6, 24, 13, 9, 26, 19, S, 0, SKIN)
	_fill_box(c, 23, 24, 13, 26, 26, 19, S, 0, SKIN)

	# Neck (y 46-47)
	_fill_box(c, 13, 46, 13, 19, 47, 19, S, 0, SKIN)

	# Head (y 48-56)
	_fill_box(c, 11, 48, 11, 21, 56, 21, S, 0, SKIN)

	# Hair (long, covering top, back, sides, hanging down)
	_fill_box(c, 11, 54, 11, 21, 57, 21, S, 0, HAIR)
	_fill_box(c, 11, 48, 11, 21, 57, 12, S, 0, HAIR)
	_fill_box(c, 11, 48, 11, 12, 57, 21, S, 0, HAIR)
	_fill_box(c, 20, 48, 11, 21, 57, 21, S, 0, HAIR)
	# Hair hanging below head (longer sides)
	_fill_box(c, 11, 40, 11, 12, 47, 14, S, 0, HAIR)
	_fill_box(c, 20, 40, 11, 21, 47, 14, S, 0, HAIR)
	# Hair down the back
	_fill_box(c, 12, 38, 11, 20, 47, 12, S, 0, HAIR)

	# Eyes (2x2 on front face)
	_fill_box(c, 13, 53, 21, 14, 54, 21, S, 0, 6)
	_fill_box(c, 18, 53, 21, 19, 54, 21, S, 0, 6)

	# Nose
	c[16][52][22] = [S, 0, SKIN]

	# Mouth
	_fill_box(c, 14, 50, 21, 18, 50, 21, S, 0, 7)

	# Navel
	c[16][36][22] = [S, 0, 4]

	def.set_from_cells(c, 32, 64, 32, 1)
	return def
