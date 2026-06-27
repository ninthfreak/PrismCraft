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
	var SK := 3; var SD := 4; var SL := 13
	var HR := 1; var EB := 12
	var EW := 6; var EP := 8; var LP := 9

	# ── Feet ──
	_fill_box(c, 11, 0, 12, 15, 0, 20, S, 0, SD)   # L sole
	_fill_box(c, 17, 0, 12, 21, 0, 20, S, 0, SD)   # R sole
	_fill_box(c, 11, 1, 12, 15, 2, 20, S, 0, SK)   # L foot
	_fill_box(c, 17, 1, 12, 21, 2, 20, S, 0, SK)   # R foot
	_fill_box(c, 12, 0, 21, 14, 1, 22, S, 0, SK)   # L toes
	_fill_box(c, 18, 0, 21, 20, 1, 22, S, 0, SK)   # R toes
	_fill_box(c, 12, 2, 17, 14, 2, 19, S, 0, SL)   # L foot top highlight
	_fill_box(c, 18, 2, 17, 20, 2, 19, S, 0, SL)   # R foot top highlight

	# ── Shins ──
	_fill_box(c, 12, 3, 13, 14, 17, 19, S, 0, SK)  # L shin
	_fill_box(c, 18, 3, 13, 20, 17, 19, S, 0, SK)  # R shin
	_fill_box(c, 12, 6, 12, 14, 10, 12, S, 0, SK)  # L calf muscle back
	_fill_box(c, 18, 6, 12, 20, 10, 12, S, 0, SK)  # R calf muscle back
	_fill_box(c, 13, 7, 19, 13, 12, 20, S, 0, SL)  # L shin front highlight
	_fill_box(c, 19, 7, 19, 19, 12, 20, S, 0, SL)  # R shin front highlight
	_fill_box(c, 14, 4, 15, 14, 14, 17, S, 0, SD)  # L inner shadow
	_fill_box(c, 18, 4, 15, 18, 14, 17, S, 0, SD)  # R inner shadow
	for bx in [12, 14, 18, 20]:
		c[bx][4][16] = [S, 0, SL]                   # Ankle bone bumps

	# ── Knees ──
	_fill_box(c, 11, 16, 12, 15, 18, 20, S, 0, SK)
	_fill_box(c, 17, 16, 12, 21, 18, 20, S, 0, SK)
	_fill_box(c, 12, 16, 20, 14, 17, 21, S, 0, SL) # L kneecap
	_fill_box(c, 18, 16, 20, 20, 17, 21, S, 0, SL) # R kneecap
	_fill_box(c, 11, 16, 12, 11, 18, 14, S, 0, SD) # L knee outer shadow
	_fill_box(c, 21, 16, 12, 21, 18, 14, S, 0, SD) # R knee outer shadow

	# ── Thighs ──
	_fill_box(c, 10, 19, 12, 15, 28, 20, S, 0, SK)
	_fill_box(c, 17, 19, 12, 22, 28, 20, S, 0, SK)
	_fill_box(c, 15, 19, 14, 15, 26, 18, S, 0, SD) # L inner shadow
	_fill_box(c, 17, 19, 14, 17, 26, 18, S, 0, SD) # R inner shadow
	_fill_box(c, 10, 21, 15, 10, 26, 17, S, 0, SL) # L outer highlight
	_fill_box(c, 22, 21, 15, 22, 26, 17, S, 0, SL) # R outer highlight
	_fill_box(c, 12, 21, 20, 13, 26, 20, S, 0, SL) # L quad highlight
	_fill_box(c, 19, 21, 20, 20, 26, 20, S, 0, SL) # R quad highlight

	# ── Pelvis ──
	_fill_box(c, 10, 27, 11, 22, 30, 21, S, 0, SK)
	_fill_box(c, 11, 29, 20, 12, 30, 21, S, 0, SL) # L hip bone
	_fill_box(c, 20, 29, 20, 21, 30, 21, S, 0, SL) # R hip bone
	_fill_box(c, 14, 27, 19, 18, 28, 21, S, 0, SD) # Groin shadow
	_fill_box(c, 13, 27, 11, 19, 29, 11, S, 0, SD) # Glute shadow

	# ── Abdomen ──
	_fill_box(c, 10, 31, 11, 22, 35, 21, S, 0, SK)
	for y in range(31, 36):
		c[16][y][22] = [S, 0, SD]                    # Linea alba
	c[16][33][22] = [S, 0, SD]                       # Navel
	_fill_box(c, 10, 31, 15, 10, 35, 17, S, 0, SD)  # L oblique shadow
	_fill_box(c, 22, 31, 15, 22, 35, 17, S, 0, SD)  # R oblique shadow
	_fill_box(c, 14, 31, 11, 18, 34, 11, S, 0, SD)  # Lower back shadow

	# ── Chest ──
	_fill_box(c, 9, 36, 10, 23, 43, 22, S, 0, SK)
	_fill_box(c, 11, 39, 22, 15, 42, 22, S, 0, SL) # L pec highlight
	_fill_box(c, 17, 39, 22, 21, 42, 22, S, 0, SL) # R pec highlight
	c[16][39][22] = [S, 0, SD]; c[16][40][22] = [S, 0, SD]; c[16][41][22] = [S, 0, SD]
	c[13][39][22] = [S, 0, LP]; c[19][39][22] = [S, 0, LP] # Nipples
	_fill_box(c, 12, 43, 21, 15, 43, 22, S, 0, SL) # L collarbone
	_fill_box(c, 17, 43, 21, 20, 43, 22, S, 0, SL) # R collarbone
	_fill_box(c, 12, 37, 10, 20, 42, 10, S, 0, SD) # Back shadow
	for y in range(36, 43):
		c[16][y][10] = [S, 0, SD]                    # Spine shadow
	_fill_box(c, 9, 36, 15, 9, 42, 17, S, 0, SD)   # L side shadow
	_fill_box(c, 23, 36, 15, 23, 42, 17, S, 0, SD)  # R side shadow
	for cx in [9, 23]:
		for cz in [10, 22]:
			c[cx][36][cz] = [E, 0, 0]               # Round lower corners
	c[9][43][10] = [E, 0, 0]; c[23][43][10] = [E, 0, 0]
	c[9][43][22] = [E, 0, 0]; c[23][43][22] = [E, 0, 0]

	# ── Shoulders ──
	_fill_box(c, 7, 42, 11, 9, 44, 21, S, 0, SK)
	_fill_box(c, 23, 42, 11, 25, 44, 21, S, 0, SK)
	_fill_box(c, 7, 44, 14, 9, 44, 18, S, 0, SL)   # L deltoid top
	_fill_box(c, 23, 44, 14, 25, 44, 18, S, 0, SL)  # R deltoid top
	c[7][44][11] = [E, 0, 0]; c[7][44][21] = [E, 0, 0]
	c[25][44][11] = [E, 0, 0]; c[25][44][21] = [E, 0, 0]
	c[7][42][11] = [E, 0, 0]; c[7][42][21] = [E, 0, 0]
	c[25][42][11] = [E, 0, 0]; c[25][42][21] = [E, 0, 0]

	# ── Upper arms ──
	_fill_box(c, 5, 33, 12, 8, 43, 20, S, 0, SK)
	_fill_box(c, 24, 33, 12, 27, 43, 20, S, 0, SK)
	_fill_box(c, 5, 37, 20, 8, 40, 20, S, 0, SL)   # L bicep
	_fill_box(c, 24, 37, 20, 27, 40, 20, S, 0, SL)  # R bicep
	_fill_box(c, 6, 34, 12, 7, 39, 12, S, 0, SD)    # L tricep shadow
	_fill_box(c, 25, 34, 12, 26, 39, 12, S, 0, SD)  # R tricep shadow
	_fill_box(c, 8, 34, 15, 8, 41, 17, S, 0, SD)    # L inner arm
	_fill_box(c, 24, 34, 15, 24, 41, 17, S, 0, SD)  # R inner arm

	# ── Forearms ──
	_fill_box(c, 5, 23, 13, 8, 32, 19, S, 0, SK)
	_fill_box(c, 24, 23, 13, 27, 32, 19, S, 0, SK)
	_fill_box(c, 6, 25, 13, 7, 29, 13, S, 0, SD)   # L underside
	_fill_box(c, 25, 25, 13, 26, 29, 13, S, 0, SD)  # R underside

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
	c[13][44][16] = [S, 0, SD]; c[19][44][16] = [S, 0, SD]
	c[13][45][16] = [S, 0, SD]; c[19][45][16] = [S, 0, SD]
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
	_fill_box(c, 12, 46, 14, 13, 47, 19, S, 0, SD)  # L jaw shadow
	_fill_box(c, 19, 46, 14, 20, 47, 19, S, 0, SD)  # R jaw shadow
	_fill_box(c, 14, 53, 20, 18, 54, 20, S, 0, SL)  # Forehead highlight
	c[13][49][20] = [S, 0, SL]; c[19][49][20] = [S, 0, SL] # Cheeks
	_fill_box(c, 14, 48, 12, 18, 52, 12, S, 0, SD)  # Back of head shadow
	c[11][49][16] = [S, 0, SK]; c[11][50][16] = [S, 0, SK]; c[11][51][16] = [S, 0, SK]
	c[21][49][16] = [S, 0, SK]; c[21][50][16] = [S, 0, SK]; c[21][51][16] = [S, 0, SK]

	# ── Face ──
	c[14][51][21] = [S, 0, EW]; c[15][51][21] = [S, 0, EP] # L eye
	c[17][51][21] = [S, 0, EP]; c[18][51][21] = [S, 0, EW] # R eye
	c[14][50][20] = [S, 0, SD]; c[15][50][20] = [S, 0, SD] # Eye socket shadow
	c[17][50][20] = [S, 0, SD]; c[18][50][20] = [S, 0, SD]
	_fill_box(c, 14, 52, 21, 15, 52, 21, S, 0, EB)  # L brow
	_fill_box(c, 17, 52, 21, 18, 52, 21, S, 0, EB)  # R brow
	c[16][49][21] = [S, 0, SK]; c[16][50][21] = [S, 0, SK] # Nose bridge
	c[16][49][22] = [S, 0, SD]                       # Nose tip
	_fill_box(c, 14, 47, 21, 18, 47, 21, S, 0, LP)  # Mouth
	c[16][48][21] = [S, 0, SD]                       # Philtrum

	# ── Hair ──
	_fill_box(c, 12, 53, 12, 20, 55, 20, S, 0, HR)  # Top crown
	_fill_box(c, 13, 53, 20, 19, 54, 20, S, 0, HR)  # Front hairline
	_fill_box(c, 12, 49, 12, 20, 55, 13, S, 0, HR)  # Back
	_fill_box(c, 12, 52, 12, 13, 55, 17, S, 0, HR)  # L side (stops before face)
	_fill_box(c, 19, 52, 12, 20, 55, 17, S, 0, HR)  # R side (stops before face)
	_fill_box(c, 14, 55, 15, 18, 55, 18, S, 0, 14)  # Top highlight

	def.set_from_cells(c, 32, 64, 32, 1)
	return def

static func create_female() -> VoxelDefinition:
	# ~1.63m tall = 52 cells, y=0..51
	var def := VoxelDefinition.new()
	var c := _make_empty_cells(32, 64, 32)
	var S := CellTypes.Type.SOLID
	var E := CellTypes.Type.EMPTY
	var SK := 3; var SD := 4; var SL := 13
	var HR := 12; var EB := 12
	var EW := 6; var EP := 8; var LP := 9

	# ── Feet ──
	_fill_box(c, 12, 0, 12, 15, 0, 20, S, 0, SD)   # L sole
	_fill_box(c, 17, 0, 12, 20, 0, 20, S, 0, SD)   # R sole
	_fill_box(c, 12, 1, 12, 15, 2, 20, S, 0, SK)   # L foot
	_fill_box(c, 17, 1, 12, 20, 2, 20, S, 0, SK)   # R foot
	_fill_box(c, 12, 0, 21, 14, 1, 22, S, 0, SK)   # L toes
	_fill_box(c, 18, 0, 21, 20, 1, 22, S, 0, SK)   # R toes
	_fill_box(c, 13, 2, 17, 14, 2, 19, S, 0, SL)   # L top highlight
	_fill_box(c, 18, 2, 17, 19, 2, 19, S, 0, SL)   # R top highlight

	# ── Shins ──
	_fill_box(c, 12, 3, 13, 15, 15, 19, S, 0, SK)
	_fill_box(c, 17, 3, 13, 20, 15, 19, S, 0, SK)
	_fill_box(c, 12, 5, 12, 15, 9, 12, S, 0, SK)   # L calf back
	_fill_box(c, 17, 5, 12, 20, 9, 12, S, 0, SK)   # R calf back
	_fill_box(c, 13, 6, 19, 14, 11, 20, S, 0, SL)  # L shin highlight
	_fill_box(c, 18, 6, 19, 19, 11, 20, S, 0, SL)  # R shin highlight
	_fill_box(c, 15, 4, 15, 15, 13, 17, S, 0, SD)  # L inner shadow
	_fill_box(c, 17, 4, 15, 17, 13, 17, S, 0, SD)  # R inner shadow
	for bx in [12, 15, 17, 20]:
		c[bx][3][16] = [S, 0, SL]                   # Ankle bones

	# ── Knees ──
	_fill_box(c, 12, 14, 12, 15, 16, 20, S, 0, SK)
	_fill_box(c, 17, 14, 12, 20, 16, 20, S, 0, SK)
	_fill_box(c, 13, 14, 20, 14, 15, 21, S, 0, SL) # L kneecap
	_fill_box(c, 18, 14, 20, 19, 15, 21, S, 0, SL) # R kneecap

	# ── Thighs (wider than male for feminine proportion) ──
	_fill_box(c, 10, 17, 12, 15, 25, 20, S, 0, SK)
	_fill_box(c, 17, 17, 12, 22, 25, 20, S, 0, SK)
	_fill_box(c, 15, 17, 14, 15, 23, 18, S, 0, SD) # L inner shadow
	_fill_box(c, 17, 17, 14, 17, 23, 18, S, 0, SD) # R inner shadow
	_fill_box(c, 10, 19, 15, 10, 24, 17, S, 0, SL) # L outer highlight
	_fill_box(c, 22, 19, 15, 22, 24, 17, S, 0, SL) # R outer highlight

	# ── Hips (wider than male, feminine) ──
	_fill_box(c, 9, 24, 10, 23, 28, 22, S, 0, SK)
	_fill_box(c, 9, 26, 20, 10, 28, 22, S, 0, SL)  # L hip highlight
	_fill_box(c, 22, 26, 20, 23, 28, 22, S, 0, SL)  # R hip highlight
	_fill_box(c, 14, 24, 20, 18, 25, 22, S, 0, SD) # Groin shadow
	_fill_box(c, 13, 24, 10, 19, 27, 10, S, 0, SD) # Glute shadow
	for cx in [9, 23]:
		c[cx][24][10] = [E, 0, 0]; c[cx][24][22] = [E, 0, 0]
		c[cx][28][10] = [E, 0, 0]; c[cx][28][22] = [E, 0, 0]

	# ── Waist (narrow, hourglass) ──
	_fill_box(c, 11, 29, 11, 21, 31, 21, S, 0, SK)
	c[16][30][22] = [S, 0, SD]                       # Navel
	_fill_box(c, 11, 29, 15, 11, 31, 17, S, 0, SD)  # L side shadow
	_fill_box(c, 21, 29, 15, 21, 31, 17, S, 0, SD)  # R side shadow

	# ── Ribcage ──
	_fill_box(c, 10, 32, 10, 22, 35, 22, S, 0, SK)
	_fill_box(c, 12, 32, 10, 20, 34, 10, S, 0, SD) # Back shadow
	for y in range(32, 36):
		c[16][y][10] = [S, 0, SD]                    # Spine
	_fill_box(c, 10, 32, 15, 10, 35, 17, S, 0, SD)  # L side shadow
	_fill_box(c, 22, 32, 15, 22, 35, 17, S, 0, SD)  # R side shadow

	# ── Chest + Breasts ──
	_fill_box(c, 10, 36, 10, 22, 39, 21, S, 0, SK)
	_fill_box(c, 12, 36, 21, 15, 38, 23, S, 0, SK) # L breast
	_fill_box(c, 17, 36, 21, 20, 38, 23, S, 0, SK) # R breast
	_fill_box(c, 13, 37, 23, 14, 37, 23, S, 0, SL) # L breast highlight
	_fill_box(c, 18, 37, 23, 19, 37, 23, S, 0, SL) # R breast highlight
	_fill_box(c, 12, 36, 22, 12, 38, 22, S, 0, SD) # L breast underside
	_fill_box(c, 20, 36, 22, 20, 38, 22, S, 0, SD) # R breast underside
	c[13][36][23] = [S, 0, LP]; c[19][36][23] = [S, 0, LP] # Nipples
	_fill_box(c, 12, 39, 21, 15, 39, 22, S, 0, SL) # L collarbone
	_fill_box(c, 17, 39, 21, 20, 39, 22, S, 0, SL) # R collarbone
	_fill_box(c, 12, 36, 10, 20, 39, 10, S, 0, SD) # Back shadow

	# ── Shoulders (narrower than male) ──
	_fill_box(c, 8, 38, 12, 10, 40, 20, S, 0, SK)
	_fill_box(c, 22, 38, 12, 24, 40, 20, S, 0, SK)
	_fill_box(c, 8, 40, 14, 10, 40, 18, S, 0, SL)  # L deltoid top
	_fill_box(c, 22, 40, 14, 24, 40, 18, S, 0, SL)  # R deltoid top
	c[8][40][12] = [E, 0, 0]; c[8][40][20] = [E, 0, 0]
	c[24][40][12] = [E, 0, 0]; c[24][40][20] = [E, 0, 0]
	c[8][38][12] = [E, 0, 0]; c[8][38][20] = [E, 0, 0]
	c[24][38][12] = [E, 0, 0]; c[24][38][20] = [E, 0, 0]

	# ── Upper arms (slimmer than male) ──
	_fill_box(c, 6, 30, 13, 9, 39, 19, S, 0, SK)
	_fill_box(c, 23, 30, 13, 26, 39, 19, S, 0, SK)
	_fill_box(c, 9, 31, 15, 9, 38, 17, S, 0, SD)   # L inner shadow
	_fill_box(c, 23, 31, 15, 23, 38, 17, S, 0, SD)  # R inner shadow
	_fill_box(c, 6, 35, 19, 9, 38, 19, S, 0, SL)   # L outer highlight
	_fill_box(c, 23, 35, 19, 26, 38, 19, S, 0, SL)  # R outer highlight

	# ── Forearms ──
	_fill_box(c, 6, 21, 14, 9, 29, 18, S, 0, SK)
	_fill_box(c, 23, 21, 14, 26, 29, 18, S, 0, SK)
	_fill_box(c, 7, 22, 14, 8, 26, 14, S, 0, SD)   # L underside
	_fill_box(c, 24, 22, 14, 25, 26, 14, S, 0, SD)  # R underside

	# ── Hands ──
	_fill_box(c, 6, 18, 14, 9, 20, 18, S, 0, SK)
	_fill_box(c, 23, 18, 14, 26, 20, 18, S, 0, SK)
	_fill_box(c, 7, 17, 14, 8, 17, 17, S, 0, SK)   # L fingers
	_fill_box(c, 24, 17, 14, 25, 17, 17, S, 0, SK)  # R fingers
	c[9][18][17] = [S, 0, SK]; c[9][17][17] = [S, 0, SK] # L thumb
	c[23][18][17] = [S, 0, SK]; c[23][17][17] = [S, 0, SK] # R thumb
	_fill_box(c, 7, 19, 16, 8, 19, 16, S, 0, LP)   # L palm
	_fill_box(c, 24, 19, 16, 25, 19, 16, S, 0, LP)  # R palm

	# ── Neck (slimmer than male) ──
	_fill_box(c, 14, 40, 14, 18, 41, 18, S, 0, SK)
	c[14][40][16] = [S, 0, SD]; c[18][40][16] = [S, 0, SD]
	c[14][41][16] = [S, 0, SD]; c[18][41][16] = [S, 0, SD]
	_fill_box(c, 12, 40, 14, 14, 40, 17, S, 0, SK)  # L trapezius
	_fill_box(c, 18, 40, 14, 20, 40, 17, S, 0, SK)  # R trapezius

	# ── Head (slightly rounder than male) ──
	_fill_box(c, 12, 42, 12, 20, 50, 20, S, 0, SK)
	for hx in [12, 20]:
		for hz in [12, 20]:
			c[hx][42][hz] = [E, 0, 0]; c[hx][50][hz] = [E, 0, 0]
		c[hx][43][12] = [E, 0, 0]; c[hx][43][20] = [E, 0, 0]
		c[hx][49][12] = [E, 0, 0]; c[hx][49][20] = [E, 0, 0]
	_fill_box(c, 14, 42, 20, 18, 42, 21, S, 0, SK)  # Chin
	_fill_box(c, 12, 42, 14, 13, 43, 19, S, 0, SD)  # L jaw shadow
	_fill_box(c, 19, 42, 14, 20, 43, 19, S, 0, SD)  # R jaw shadow
	_fill_box(c, 14, 49, 20, 18, 50, 20, S, 0, SL)  # Forehead highlight
	c[13][46][20] = [S, 0, SL]; c[19][46][20] = [S, 0, SL] # Cheek blush
	c[14][46][20] = [S, 0, LP]; c[18][46][20] = [S, 0, LP] # Blush pink
	_fill_box(c, 14, 44, 12, 18, 48, 12, S, 0, SD)  # Back of head shadow
	c[11][46][16] = [S, 0, SK]; c[11][47][16] = [S, 0, SK] # L ear
	c[21][46][16] = [S, 0, SK]; c[21][47][16] = [S, 0, SK] # R ear

	# ── Face (larger eyes, softer features) ──
	_fill_box(c, 13, 47, 21, 14, 48, 21, S, 0, EW)  # L eye white
	c[14][48][21] = [S, 0, EP]; c[14][47][21] = [S, 0, EP] # L pupil
	_fill_box(c, 18, 47, 21, 19, 48, 21, S, 0, EW)  # R eye white
	c[18][48][21] = [S, 0, EP]; c[18][47][21] = [S, 0, EP] # R pupil
	_fill_box(c, 13, 49, 21, 14, 49, 21, S, 0, EB)  # L brow
	_fill_box(c, 18, 49, 21, 19, 49, 21, S, 0, EB)  # R brow
	c[16][46][21] = [S, 0, SK]; c[16][45][21] = [S, 0, SK] # Nose
	c[16][45][22] = [S, 0, SD]                       # Nose tip
	_fill_box(c, 15, 44, 21, 17, 44, 21, S, 0, LP)  # Mouth (smaller, pink)
	c[14][44][21] = [S, 0, LP]; c[18][44][21] = [S, 0, LP] # Lip corners

	# ── Hair (long, dark brown) ──
	_fill_box(c, 12, 49, 12, 20, 51, 20, S, 0, HR)  # Top crown
	_fill_box(c, 13, 49, 20, 19, 50, 20, S, 0, HR)  # Bangs (partial, leaves face open)
	_fill_box(c, 12, 42, 12, 20, 51, 13, S, 0, HR)  # Back
	_fill_box(c, 12, 45, 12, 13, 51, 17, S, 0, HR)  # L side (stops before face)
	_fill_box(c, 19, 45, 12, 20, 51, 17, S, 0, HR)  # R side (stops before face)
	_fill_box(c, 11, 34, 12, 12, 44, 15, S, 0, HR)  # L hanging
	_fill_box(c, 20, 34, 12, 21, 44, 15, S, 0, HR)  # R hanging
	_fill_box(c, 13, 32, 12, 19, 44, 12, S, 0, HR)  # Back long hair
	_fill_box(c, 14, 51, 15, 18, 51, 18, S, 0, 14)  # Top highlight

	def.set_from_cells(c, 32, 64, 32, 1)
	return def
