extends Node3D


func _ready() -> void:
	var world_node: World = $World
	var player_node: CharacterBody3D = $Player

	player_node.world = world_node
	world_node.player = player_node

	# Place player above terrain at spawn point
	var spawn_x := 8
	var spawn_z := 8
	var spawn_y := world_node.get_terrain_height(spawn_x, spawn_z) + 10
	player_node.position = Vector3(spawn_x, spawn_y, spawn_z)

	world_node.load_initial_chunks(player_node.position)
