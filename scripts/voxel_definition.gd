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
	# ~1.75m tall = 56 cells, standing on y=0..y=55
	var def := VoxelDefinition.new()
	var c := _make_empty_cells(32, 64, 32)
	var S := CellTypes.Type.SOLID
	var SKIN := 3
	var HAIR := 1

	_fill_box(c, 11, 0, 12, 15, 2, 20, S, 0, SKIN)   # L foot
	_fill_box(c, 17, 0, 12, 21, 2, 20, S, 0, SKIN)   # R foot
	_fill_box(c, 12, 3, 13, 14, 17, 19, S, 0, SKIN)  # L shin
	_fill_box(c, 18, 3, 13, 20, 17, 19, S, 0, SKIN)  # R shin
	_fill_box(c, 11, 16, 12, 15, 18, 20, S, 0, SKIN) # L knee
	_fill_box(c, 17, 16, 12, 21, 18, 20, S, 0, SKIN) # R knee
	_fill_box(c, 10, 19, 12, 15, 28, 20, S, 0, SKIN) # L thigh
	_fill_box(c, 17, 19, 12, 22, 28, 20, S, 0, SKIN) # R thigh
	_fill_box(c, 10, 27, 11, 22, 30, 21, S, 0, SKIN) # Pelvis
	_fill_box(c, 10, 31, 11, 22, 35, 21, S, 0, SKIN) # Abdomen
	_fill_box(c, 9, 36, 10, 23, 43, 22, S, 0, SKIN)  # Chest
	c[12][39][22] = [S, 0, 4]                          # L nipple
	c[20][39][22] = [S, 0, 4]                          # R nipple
	_fill_box(c, 7, 42, 11, 9, 44, 21, S, 0, SKIN)   # L shoulder
	_fill_box(c, 23, 42, 11, 25, 44, 21, S, 0, SKIN) # R shoulder
	_fill_box(c, 5, 33, 12, 8, 43, 20, S, 0, SKIN)   # L upper arm
	_fill_box(c, 24, 33, 12, 27, 43, 20, S, 0, SKIN) # R upper arm
	_fill_box(c, 5, 23, 13, 8, 32, 19, S, 0, SKIN)   # L forearm
	_fill_box(c, 24, 23, 13, 27, 32, 19, S, 0, SKIN) # R forearm
	_fill_box(c, 5, 20, 12, 8, 22, 19, S, 0, SKIN)   # L hand
	_fill_box(c, 24, 20, 12, 27, 22, 19, S, 0, SKIN) # R hand
	_fill_box(c, 13, 44, 13, 19, 45, 19, S, 0, SKIN) # Neck
	_fill_box(c, 11, 46, 11, 21, 54, 21, S, 0, SKIN) # Head
	_fill_box(c, 11, 52, 11, 21, 55, 21, S, 0, HAIR) # Hair top
	_fill_box(c, 11, 48, 11, 21, 55, 12, S, 0, HAIR) # Hair back
	_fill_box(c, 13, 51, 21, 14, 52, 21, S, 0, 6)    # L eye
	_fill_box(c, 18, 51, 21, 19, 52, 21, S, 0, 6)    # R eye
	c[16][50][22] = [S, 0, SKIN]                       # Nose
	_fill_box(c, 14, 48, 21, 18, 48, 21, S, 0, 7)    # Mouth
	c[16][33][22] = [S, 0, 4]                          # Navel

	def.set_from_cells(c, 32, 64, 32, 1)
	return def

static func create_female() -> VoxelDefinition:
	# ~1.63m tall = 52 cells, standing on y=0..y=51
	var def := VoxelDefinition.new()
	var c := _make_empty_cells(32, 64, 32)
	var S := CellTypes.Type.SOLID
	var SKIN := 3
	var HAIR := 1

	_fill_box(c, 12, 0, 12, 15, 2, 20, S, 0, SKIN)   # L foot
	_fill_box(c, 17, 0, 12, 20, 2, 20, S, 0, SKIN)   # R foot
	_fill_box(c, 12, 3, 13, 15, 15, 19, S, 0, SKIN)  # L shin
	_fill_box(c, 17, 3, 13, 20, 15, 19, S, 0, SKIN)  # R shin
	_fill_box(c, 12, 14, 12, 15, 16, 20, S, 0, SKIN) # L knee
	_fill_box(c, 17, 14, 12, 20, 16, 20, S, 0, SKIN) # R knee
	_fill_box(c, 10, 17, 12, 15, 25, 20, S, 0, SKIN) # L thigh
	_fill_box(c, 17, 17, 12, 22, 25, 20, S, 0, SKIN) # R thigh
	_fill_box(c, 9, 24, 10, 23, 28, 22, S, 0, SKIN)  # Hips
	_fill_box(c, 11, 29, 11, 21, 31, 21, S, 0, SKIN) # Waist
	_fill_box(c, 10, 32, 10, 22, 35, 22, S, 0, SKIN) # Ribcage
	_fill_box(c, 10, 36, 10, 22, 39, 21, S, 0, SKIN) # Chest
	_fill_box(c, 12, 36, 21, 15, 38, 22, S, 0, SKIN) # L breast
	_fill_box(c, 17, 36, 21, 20, 38, 22, S, 0, SKIN) # R breast
	c[13][37][23] = [S, 0, 4]                          # L nipple
	c[19][37][23] = [S, 0, 4]                          # R nipple
	_fill_box(c, 8, 38, 12, 10, 40, 20, S, 0, SKIN)  # L shoulder
	_fill_box(c, 22, 38, 12, 24, 40, 20, S, 0, SKIN) # R shoulder
	_fill_box(c, 6, 30, 13, 9, 39, 19, S, 0, SKIN)   # L upper arm
	_fill_box(c, 23, 30, 13, 26, 39, 19, S, 0, SKIN) # R upper arm
	_fill_box(c, 6, 21, 13, 9, 29, 19, S, 0, SKIN)   # L forearm
	_fill_box(c, 23, 21, 13, 26, 29, 19, S, 0, SKIN) # R forearm
	_fill_box(c, 6, 18, 13, 9, 20, 19, S, 0, SKIN)   # L hand
	_fill_box(c, 23, 18, 13, 26, 20, 19, S, 0, SKIN) # R hand
	_fill_box(c, 13, 40, 13, 19, 41, 19, S, 0, SKIN) # Neck
	_fill_box(c, 11, 42, 11, 21, 50, 21, S, 0, SKIN) # Head
	_fill_box(c, 11, 48, 11, 21, 51, 21, S, 0, HAIR) # Hair top
	_fill_box(c, 11, 42, 11, 21, 51, 12, S, 0, HAIR) # Hair back
	_fill_box(c, 11, 42, 11, 12, 51, 21, S, 0, HAIR) # Hair L side
	_fill_box(c, 20, 42, 11, 21, 51, 21, S, 0, HAIR) # Hair R side
	_fill_box(c, 11, 34, 11, 12, 41, 14, S, 0, HAIR) # L hanging
	_fill_box(c, 20, 34, 11, 21, 41, 14, S, 0, HAIR) # R hanging
	_fill_box(c, 12, 32, 11, 20, 41, 12, S, 0, HAIR) # Back hair
	_fill_box(c, 13, 47, 21, 14, 48, 21, S, 0, 6)    # L eye
	_fill_box(c, 18, 47, 21, 19, 48, 21, S, 0, 6)    # R eye
	c[16][46][22] = [S, 0, SKIN]                       # Nose
	_fill_box(c, 14, 44, 21, 18, 44, 21, S, 0, 7)    # Mouth
	c[16][30][22] = [S, 0, 4]                          # Navel

	def.set_from_cells(c, 32, 64, 32, 1)
	return def
