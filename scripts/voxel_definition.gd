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
	# ~1.75m tall = 56 cells, y=0..55
	var def := VoxelDefinition.new()
	var c := _make_empty_cells(32, 64, 32)
	var S := CellTypes.Type.SOLID
	var E := CellTypes.Type.EMPTY
	var SK := 3; var SD := 4
	var HR := 1; var EB := 12
	var EW := 6; var EP := 8; var LP := 9

	# ── Feet ──
	_fill_box(c, 11, 0, 12, 15, 0, 20, S, 0, SD)   # L sole
	_fill_box(c, 17, 0, 12, 21, 0, 20, S, 0, SD)   # R sole
	_fill_box(c, 11, 1, 12, 15, 2, 20, S, 0, SK)   # L foot
	_fill_box(c, 17, 1, 12, 21, 2, 20, S, 0, SK)   # R foot
	_fill_box(c, 12, 0, 21, 14, 1, 22, S, 0, SK)   # L toes
	_fill_box(c, 18, 0, 21, 20, 1, 22, S, 0, SK)   # R toes

	# ── Shins ──
	_fill_box(c, 12, 3, 13, 14, 17, 19, S, 0, SK)  # L shin
	_fill_box(c, 18, 3, 13, 20, 17, 19, S, 0, SK)  # R shin
	_fill_box(c, 12, 6, 12, 14, 10, 12, S, 0, SK)  # L calf muscle
	_fill_box(c, 18, 6, 12, 20, 10, 12, S, 0, SK)  # R calf muscle
	for bx in [12, 14, 18, 20]:
		c[bx][4][16] = [S, 0, SK]                   # Ankle bones

	# ── Knees ──
	_fill_box(c, 11, 16, 12, 15, 18, 20, S, 0, SK)
	_fill_box(c, 17, 16, 12, 21, 18, 20, S, 0, SK)
	_fill_box(c, 12, 16, 20, 14, 17, 21, S, 0, SK) # L kneecap
	_fill_box(c, 18, 16, 20, 20, 17, 21, S, 0, SK) # R kneecap

	# ── Thighs ──
	_fill_box(c, 10, 19, 12, 15, 28, 20, S, 0, SK)
	_fill_box(c, 17, 19, 12, 22, 28, 20, S, 0, SK)

	# ── Pelvis ──
	_fill_box(c, 10, 27, 11, 22, 30, 21, S, 0, SK)

	# ── Abdomen ──
	_fill_box(c, 10, 31, 11, 22, 35, 21, S, 0, SK)
	c[16][33][22] = [S, 0, SD]                       # Navel

	# ── Chest ──
	_fill_box(c, 9, 36, 10, 23, 43, 22, S, 0, SK)
	c[13][39][22] = [S, 0, LP]; c[19][39][22] = [S, 0, LP] # Nipples
	for cx in [9, 23]:
		for cz in [10, 22]:
			c[cx][36][cz] = [E, 0, 0]               # Round lower corners
	c[9][43][10] = [E, 0, 0]; c[23][43][10] = [E, 0, 0]
	c[9][43][22] = [E, 0, 0]; c[23][43][22] = [E, 0, 0]

	# ── Shoulders ──
	_fill_box(c, 7, 42, 11, 9, 44, 21, S, 0, SK)
	_fill_box(c, 23, 42, 11, 25, 44, 21, S, 0, SK)
	c[7][44][11] = [E, 0, 0]; c[7][44][21] = [E, 0, 0]
	c[25][44][11] = [E, 0, 0]; c[25][44][21] = [E, 0, 0]
	c[7][42][11] = [E, 0, 0]; c[7][42][21] = [E, 0, 0]
	c[25][42][11] = [E, 0, 0]; c[25][42][21] = [E, 0, 0]

	# ── Upper arms ──
	_fill_box(c, 5, 33, 12, 8, 43, 20, S, 0, SK)
	_fill_box(c, 24, 33, 12, 27, 43, 20, S, 0, SK)

	# ── Forearms ──
	_fill_box(c, 5, 23, 13, 8, 32, 19, S, 0, SK)
	_fill_box(c, 24, 23, 13, 27, 32, 19, S, 0, SK)

	# ── Hands ──
	_fill_box(c, 5, 20, 13, 8, 22, 19, S, 0, SK)
	_fill_box(c, 24, 20, 13, 27, 22, 19, S, 0, SK)
	_fill_box(c, 6, 19, 14, 7, 19, 18, S, 0, SK)   # L fingers
	_fill_box(c, 25, 19, 14, 26, 19, 18, S, 0, SK)  # R fingers
	c[8][20][18] = [S, 0, SK]; c[8][19][18] = [S, 0, SK] # L thumb
	c[24][20][18] = [S, 0, SK]; c[24][19][18] = [S, 0, SK] # R thumb
	_fill_box(c, 6, 20, 16, 7, 21, 16, S, 0, LP)   # L palm
	_fill_box(c, 25, 20, 16, 26, 21, 16, S, 0, LP)  # R palm

	# ── Neck ──
	_fill_box(c, 13, 44, 13, 19, 45, 19, S, 0, SK)
	c[16][44][20] = [S, 0, SK]                       # Adam's apple
	_fill_box(c, 11, 44, 13, 13, 44, 17, S, 0, SK)  # L trapezius
	_fill_box(c, 19, 44, 13, 21, 44, 17, S, 0, SK)  # R trapezius

	# ── Head ──
	_fill_box(c, 12, 46, 12, 20, 54, 20, S, 0, SK)
	for hx in [12, 20]:
		for hz in [12, 20]:
			c[hx][46][hz] = [E, 0, 0]; c[hx][54][hz] = [E, 0, 0]
		c[hx][47][12] = [E, 0, 0]; c[hx][47][20] = [E, 0, 0]
		c[hx][53][12] = [E, 0, 0]; c[hx][53][20] = [E, 0, 0]
	_fill_box(c, 14, 46, 20, 18, 46, 21, S, 0, SK)  # Chin
	c[11][49][16] = [S, 0, SK]; c[11][50][16] = [S, 0, SK]; c[11][51][16] = [S, 0, SK]
	c[21][49][16] = [S, 0, SK]; c[21][50][16] = [S, 0, SK]; c[21][51][16] = [S, 0, SK]

	# ── Face ──
	c[14][51][21] = [S, 0, EW]; c[15][51][21] = [S, 0, EP] # L eye
	c[17][51][21] = [S, 0, EP]; c[18][51][21] = [S, 0, EW] # R eye
	_fill_box(c, 14, 52, 21, 15, 52, 21, S, 0, EB)  # L brow
	_fill_box(c, 17, 52, 21, 18, 52, 21, S, 0, EB)  # R brow
	c[16][49][21] = [S, 0, SK]; c[16][50][21] = [S, 0, SK] # Nose
	_fill_box(c, 14, 47, 21, 18, 47, 21, S, 0, LP)  # Mouth

	# ── Hair ──
	_fill_box(c, 12, 53, 12, 20, 55, 20, S, 0, HR)  # Top crown
	_fill_box(c, 13, 53, 20, 19, 54, 20, S, 0, HR)  # Front hairline
	_fill_box(c, 12, 49, 12, 20, 55, 13, S, 0, HR)  # Back
	_fill_box(c, 12, 52, 12, 13, 55, 17, S, 0, HR)  # L side
	_fill_box(c, 19, 52, 12, 20, 55, 17, S, 0, HR)  # R side

	def.set_from_cells(c, 32, 64, 32, 1)
	return def

static func create_female() -> VoxelDefinition:
	# ~1.63m tall = 52 cells, y=0..51
	var def := VoxelDefinition.new()
	var c := _make_empty_cells(32, 64, 32)
	var S := CellTypes.Type.SOLID
	var E := CellTypes.Type.EMPTY
	var SK := 3; var SD := 4
	var HR := 12; var EB := 12
	var EW := 6; var EP := 8; var LP := 9

	# ── Feet ──
	_fill_box(c, 12, 0, 12, 15, 0, 20, S, 0, SD)   # L sole
	_fill_box(c, 17, 0, 12, 20, 0, 20, S, 0, SD)   # R sole
	_fill_box(c, 12, 1, 12, 15, 2, 20, S, 0, SK)   # L foot
	_fill_box(c, 17, 1, 12, 20, 2, 20, S, 0, SK)   # R foot
	_fill_box(c, 12, 0, 21, 14, 1, 22, S, 0, SK)   # L toes
	_fill_box(c, 18, 0, 21, 20, 1, 22, S, 0, SK)   # R toes

	# ── Shins ──
	_fill_box(c, 12, 3, 13, 15, 15, 19, S, 0, SK)
	_fill_box(c, 17, 3, 13, 20, 15, 19, S, 0, SK)
	_fill_box(c, 12, 5, 12, 15, 9, 12, S, 0, SK)   # L calf
	_fill_box(c, 17, 5, 12, 20, 9, 12, S, 0, SK)   # R calf
	for bx in [12, 15, 17, 20]:
		c[bx][3][16] = [S, 0, SK]                   # Ankle bones

	# ── Knees ──
	_fill_box(c, 12, 14, 12, 15, 16, 20, S, 0, SK)
	_fill_box(c, 17, 14, 12, 20, 16, 20, S, 0, SK)
	_fill_box(c, 13, 14, 20, 14, 15, 21, S, 0, SK) # L kneecap
	_fill_box(c, 18, 14, 20, 19, 15, 21, S, 0, SK) # R kneecap

	# ── Thighs ──
	_fill_box(c, 10, 17, 12, 15, 25, 20, S, 0, SK)
	_fill_box(c, 17, 17, 12, 22, 25, 20, S, 0, SK)

	# ── Hips ──
	_fill_box(c, 9, 24, 10, 23, 27, 22, S, 0, SK)
	_fill_box(c, 10, 28, 10, 22, 28, 22, S, 0, SK)  # Transition row (narrower)
	for cx in [9, 23]:
		c[cx][24][10] = [E, 0, 0]; c[cx][24][22] = [E, 0, 0]
		c[cx][27][10] = [E, 0, 0]; c[cx][27][22] = [E, 0, 0]

	# ── Waist ──
	_fill_box(c, 10, 29, 11, 22, 31, 21, S, 0, SK)  # Wider waist (was 11-21)
	c[16][30][22] = [S, 0, SD]                       # Navel

	# ── Ribcage ──
	_fill_box(c, 10, 32, 10, 22, 35, 22, S, 0, SK)

	# ── Chest + Breasts ──
	_fill_box(c, 10, 36, 10, 22, 39, 22, S, 0, SK)  # Upper chest
	_fill_box(c, 11, 34, 22, 15, 37, 23, S, 0, SK)  # L breast (lower, wider)
	_fill_box(c, 17, 34, 22, 21, 37, 23, S, 0, SK)  # R breast
	_fill_box(c, 12, 34, 23, 14, 36, 24, S, 0, SK)  # L breast center
	_fill_box(c, 18, 34, 23, 20, 36, 24, S, 0, SK)  # R breast center
	c[13][35][24] = [S, 0, LP]; c[19][35][24] = [S, 0, LP] # Nipples

	# ── Shoulders ──
	_fill_box(c, 8, 38, 12, 10, 40, 20, S, 0, SK)
	_fill_box(c, 22, 38, 12, 24, 40, 20, S, 0, SK)
	c[8][40][12] = [E, 0, 0]; c[8][40][20] = [E, 0, 0]
	c[24][40][12] = [E, 0, 0]; c[24][40][20] = [E, 0, 0]
	c[8][38][12] = [E, 0, 0]; c[8][38][20] = [E, 0, 0]
	c[24][38][12] = [E, 0, 0]; c[24][38][20] = [E, 0, 0]

	# ── Upper arms ──
	_fill_box(c, 6, 30, 13, 9, 39, 19, S, 0, SK)
	_fill_box(c, 23, 30, 13, 26, 39, 19, S, 0, SK)

	# ── Forearms ──
	_fill_box(c, 6, 21, 14, 9, 29, 18, S, 0, SK)
	_fill_box(c, 23, 21, 14, 26, 29, 18, S, 0, SK)

	# ── Hands ──
	_fill_box(c, 6, 18, 14, 9, 20, 18, S, 0, SK)
	_fill_box(c, 23, 18, 14, 26, 20, 18, S, 0, SK)
	_fill_box(c, 7, 17, 14, 8, 17, 17, S, 0, SK)   # L fingers
	_fill_box(c, 24, 17, 14, 25, 17, 17, S, 0, SK)  # R fingers
	c[9][18][17] = [S, 0, SK]; c[9][17][17] = [S, 0, SK] # L thumb
	c[23][18][17] = [S, 0, SK]; c[23][17][17] = [S, 0, SK] # R thumb
	_fill_box(c, 7, 19, 16, 8, 19, 16, S, 0, LP)   # L palm
	_fill_box(c, 24, 19, 16, 25, 19, 16, S, 0, LP)  # R palm

	# ── Neck ──
	_fill_box(c, 14, 40, 14, 18, 41, 18, S, 0, SK)
	_fill_box(c, 12, 40, 14, 14, 40, 17, S, 0, SK)  # L trapezius
	_fill_box(c, 18, 40, 14, 20, 40, 17, S, 0, SK)  # R trapezius

	# ── Head ──
	_fill_box(c, 12, 42, 12, 20, 50, 20, S, 0, SK)
	for hx in [12, 20]:
		for hz in [12, 20]:
			c[hx][42][hz] = [E, 0, 0]; c[hx][50][hz] = [E, 0, 0]
		c[hx][43][12] = [E, 0, 0]; c[hx][43][20] = [E, 0, 0]
		c[hx][49][12] = [E, 0, 0]; c[hx][49][20] = [E, 0, 0]
	_fill_box(c, 14, 42, 20, 18, 42, 21, S, 0, SK)  # Chin
	c[11][46][16] = [S, 0, SK]; c[11][47][16] = [S, 0, SK] # L ear
	c[21][46][16] = [S, 0, SK]; c[21][47][16] = [S, 0, SK] # R ear

	# ── Face ──
	_fill_box(c, 13, 47, 21, 14, 48, 21, S, 0, EW)  # L eye white
	c[14][48][21] = [S, 0, EP]; c[14][47][21] = [S, 0, EP] # L pupil
	_fill_box(c, 18, 47, 21, 19, 48, 21, S, 0, EW)  # R eye white
	c[18][48][21] = [S, 0, EP]; c[18][47][21] = [S, 0, EP] # R pupil
	_fill_box(c, 13, 49, 21, 14, 49, 21, S, 0, EB)  # L brow
	_fill_box(c, 18, 49, 21, 19, 49, 21, S, 0, EB)  # R brow
	c[16][46][21] = [S, 0, SK]; c[16][45][21] = [S, 0, SK] # Nose
	_fill_box(c, 15, 44, 21, 17, 44, 21, S, 0, LP)  # Mouth
	c[14][44][21] = [S, 0, LP]; c[18][44][21] = [S, 0, LP] # Lip corners

	# ── Hair (long, dark brown) ──
	_fill_box(c, 12, 49, 12, 20, 51, 20, S, 0, HR)  # Top crown
	_fill_box(c, 13, 49, 20, 19, 50, 20, S, 0, HR)  # Bangs
	_fill_box(c, 12, 42, 12, 20, 51, 13, S, 0, HR)  # Back
	_fill_box(c, 12, 45, 12, 13, 51, 17, S, 0, HR)  # L side
	_fill_box(c, 19, 45, 12, 20, 51, 17, S, 0, HR)  # R side
	_fill_box(c, 11, 34, 12, 12, 44, 15, S, 0, HR)  # L hanging
	_fill_box(c, 20, 34, 12, 21, 44, 15, S, 0, HR)  # R hanging
	_fill_box(c, 13, 32, 12, 19, 44, 12, S, 0, HR)  # Back long hair

	def.set_from_cells(c, 32, 64, 32, 1)
	return def
