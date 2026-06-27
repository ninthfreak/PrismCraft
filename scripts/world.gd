class_name World
extends Node3D

const RENDER_DISTANCE := 6

var chunks: Dictionary = {}
var noise: FastNoiseLite
var player: Node3D
var _chunk_material: StandardMaterial3D
var _load_queue: Array = []
var _queued: Dictionary = {}
var _last_player_chunk := Vector2i(-99999, -99999)


func _ready() -> void:
	noise = FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.012
	noise.seed = randi()

	_chunk_material = StandardMaterial3D.new()
	_chunk_material.vertex_color_use_as_albedo = true


func _process(_delta: float) -> void:
	if not player:
		return

	var pcx := floori(player.global_position.x / float(Chunk.SIZE))
	var pcz := floori(player.global_position.z / float(Chunk.SIZE))
	var current := Vector2i(pcx, pcz)

	if current != _last_player_chunk:
		_last_player_chunk = current
		_rebuild_load_queue(pcx, pcz)
		_unload_distant_chunks(pcx, pcz)

	var loaded := 0
	while _load_queue.size() > 0 and loaded < 2:
		var key: Vector2i = _load_queue.pop_front()
		_queued.erase(key)
		if key not in chunks:
			_create_and_build_chunk(key.x, key.y)
			loaded += 1


func load_initial_chunks(pos: Vector3) -> void:
	var pcx := floori(pos.x / float(Chunk.SIZE))
	var pcz := floori(pos.z / float(Chunk.SIZE))

	# First pass: create chunks and fill terrain
	for dx in range(-2, 3):
		for dz in range(-2, 3):
			_create_chunk(pcx + dx, pcz + dz)

	# Second pass: generate meshes (so cross-chunk face culling works)
	for key in chunks:
		chunks[key].generate_mesh()

	_last_player_chunk = Vector2i(pcx, pcz)


func get_block_at(wx: int, wy: int, wz: int, sub: int) -> int:
	var cx := floori(float(wx) / Chunk.SIZE)
	var cz := floori(float(wz) / Chunk.SIZE)
	var key := Vector2i(cx, cz)
	if key in chunks:
		var lx := wx - cx * Chunk.SIZE
		var lz := wz - cz * Chunk.SIZE
		return chunks[key].get_block(lx, wy, lz, sub)
	return BlockTypes.Type.AIR


func set_block_at(wx: int, wy: int, wz: int, sub: int, block_type: int) -> void:
	var cx := floori(float(wx) / Chunk.SIZE)
	var cz := floori(float(wz) / Chunk.SIZE)
	var key := Vector2i(cx, cz)
	if key not in chunks:
		return
	var lx := wx - cx * Chunk.SIZE
	var lz := wz - cz * Chunk.SIZE
	chunks[key].set_block(lx, wy, lz, sub, block_type)
	chunks[key].generate_mesh()

	# Regenerate neighbor chunk meshes at borders
	if lx == 0:
		_regen_chunk(cx - 1, cz)
	elif lx == Chunk.SIZE - 1:
		_regen_chunk(cx + 1, cz)
	if lz == 0:
		_regen_chunk(cx, cz - 1)
	elif lz == Chunk.SIZE - 1:
		_regen_chunk(cx, cz + 1)


func get_terrain_height(wx: int, wz: int) -> int:
	var n := noise.get_noise_2d(float(wx), float(wz))
	return int((n + 1.0) * 0.5 * 24.0) + 8


func _create_chunk(cx: int, cz: int) -> void:
	var key := Vector2i(cx, cz)
	if key in chunks:
		return
	var chunk := Chunk.new()
	chunk.initialize(cx, cz, self, _chunk_material)
	add_child(chunk)
	chunks[key] = chunk
	_generate_terrain(chunk)
	_place_trees(chunk)


func _create_and_build_chunk(cx: int, cz: int) -> void:
	_create_chunk(cx, cz)
	var key := Vector2i(cx, cz)
	chunks[key].generate_mesh()

	# Rebuild adjacent chunks for correct face culling at borders
	for d in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
		var adj := key + d
		if adj in chunks:
			chunks[adj].generate_mesh()


func _generate_terrain(chunk: Chunk) -> void:
	for lx in Chunk.SIZE:
		for lz in Chunk.SIZE:
			var wx := chunk.chunk_x * Chunk.SIZE + lx
			var wz := chunk.chunk_z * Chunk.SIZE + lz
			var h := get_terrain_height(wx, wz)

			for y in range(0, h + 1):
				var bt: int
				if y == h:
					bt = BlockTypes.Type.GRASS if h > 13 else BlockTypes.Type.SAND
				elif y > h - 4:
					bt = BlockTypes.Type.DIRT
				else:
					bt = BlockTypes.Type.STONE
				chunk.set_block(lx, y, lz, 0, bt)
				chunk.set_block(lx, y, lz, 1, bt)


func _place_trees(chunk: Chunk) -> void:
	for lx in range(2, Chunk.SIZE - 2):
		for lz in range(2, Chunk.SIZE - 2):
			var wx := chunk.chunk_x * Chunk.SIZE + lx
			var wz := chunk.chunk_z * Chunk.SIZE + lz
			var h := get_terrain_height(wx, wz)

			if h <= 14:
				continue

			var hv := _hash_pos(wx, wz)
			if hv % 50 != 0:
				continue

			var trunk_h := 4 + (hv / 50) % 3

			for y in range(h + 1, h + 1 + trunk_h):
				chunk.set_block(lx, y, lz, 0, BlockTypes.Type.WOOD)
				chunk.set_block(lx, y, lz, 1, BlockTypes.Type.WOOD)

			var leaf_base := h + trunk_h - 1
			for dy in range(0, 4):
				var radius := 2 if dy < 2 else 1
				if dy == 3:
					radius = 0
				for dx in range(-radius, radius + 1):
					for dz in range(-radius, radius + 1):
						if radius == 2 and abs(dx) == 2 and abs(dz) == 2:
							continue
						var tx := lx + dx
						var tz := lz + dz
						var ty := leaf_base + dy
						if tx >= 0 and tx < Chunk.SIZE and tz >= 0 and tz < Chunk.SIZE and ty < Chunk.HEIGHT:
							if chunk.get_block(tx, ty, tz, 0) == BlockTypes.Type.AIR:
								chunk.set_block(tx, ty, tz, 0, BlockTypes.Type.LEAVES)
								chunk.set_block(tx, ty, tz, 1, BlockTypes.Type.LEAVES)


func _hash_pos(x: int, z: int) -> int:
	var h := x * 374761393 + z * 668265263
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return absi(h)


func _rebuild_load_queue(pcx: int, pcz: int) -> void:
	_load_queue.clear()
	_queued.clear()
	var entries: Array = []

	for dx in range(-RENDER_DISTANCE, RENDER_DISTANCE + 1):
		for dz in range(-RENDER_DISTANCE, RENDER_DISTANCE + 1):
			var key := Vector2i(pcx + dx, pcz + dz)
			if key not in chunks:
				entries.append({"key": key, "dist": dx * dx + dz * dz})

	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.dist < b.dist)
	for e in entries:
		_load_queue.append(e.key)
		_queued[e.key] = true


func _unload_distant_chunks(pcx: int, pcz: int) -> void:
	var to_remove: Array = []
	for key: Vector2i in chunks:
		if absi(key.x - pcx) > RENDER_DISTANCE + 2 or absi(key.y - pcz) > RENDER_DISTANCE + 2:
			to_remove.append(key)
	for key in to_remove:
		chunks[key].queue_free()
		chunks.erase(key)


func _regen_chunk(cx: int, cz: int) -> void:
	var key := Vector2i(cx, cz)
	if key in chunks:
		chunks[key].generate_mesh()
