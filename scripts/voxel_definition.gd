class_name VoxelDefinition
extends Resource

@export var grid_x: int = 16
@export var grid_y: int = 16
@export var grid_z: int = 16
@export var cell_data: PackedInt32Array = PackedInt32Array()
# Atlas layout this block was textured as (uniform/capped/net/octagon_*/shape),
# so the Texture Editor can rebuild the right atlas from the cells after a
# reload. Empty = unknown (the editor falls back to guessing from geometry).
@export var block_shape: String = ""

func set_from_cells(p_cells: Array, gx: int, gy: int, gz: int) -> void:
	grid_x = gx
	grid_y = gy
	grid_z = gz
	cell_data.resize(gx * gy * gz * 8)
	for x in range(gx):
		for y in range(gy):
			for z in range(gz):
				var idx := (x * gy * gz + y * gz + z) * 8
				var cell: Array = p_cells[x][y][z]
				for i in range(8):
					cell_data[idx + i] = cell[i]

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
				var idx := (x * grid_y * grid_z + y * grid_z + z) * 8
				if idx + 7 < cell_data.size():
					var cell: Array = []
					cell.resize(8)
					for i in range(8):
						cell[i] = cell_data[idx + i]
					p_cells[x][y][z] = cell
				else:
					p_cells[x][y][z] = CellTypes.empty_cell()
	return p_cells
