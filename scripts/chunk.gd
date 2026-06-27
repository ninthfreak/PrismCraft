class_name Chunk
extends Node3D

const SIZE := 16
const HEIGHT := 64
const HYPO_NORMAL_A := Vector3(0.70711, 0.0, 0.70711)
const HYPO_NORMAL_B := Vector3(-0.70711, 0.0, -0.70711)

var chunk_x: int
var chunk_z: int
var blocks: Array
var max_height: int = 0
var world_ref: Node

var _mesh_instance: MeshInstance3D
var _collision_body: StaticBody3D
var _collision_shape: CollisionShape3D
var _material: StandardMaterial3D


func initialize(cx: int, cz: int, world: Node, material: StandardMaterial3D) -> void:
	chunk_x = cx
	chunk_z = cz
	world_ref = world
	_material = material
	position = Vector3(cx * SIZE, 0, cz * SIZE)

	blocks = []
	blocks.resize(SIZE)
	for x in SIZE:
		blocks[x] = []
		blocks[x].resize(HEIGHT)
		for y in HEIGHT:
			blocks[x][y] = []
			blocks[x][y].resize(SIZE)
			for z in SIZE:
				blocks[x][y][z] = [BlockTypes.Type.AIR, BlockTypes.Type.AIR]

	_mesh_instance = MeshInstance3D.new()
	add_child(_mesh_instance)

	_collision_body = StaticBody3D.new()
	add_child(_collision_body)
	_collision_shape = CollisionShape3D.new()
	_collision_body.add_child(_collision_shape)


func get_block(lx: int, ly: int, lz: int, sub: int) -> int:
	if lx < 0 or lx >= SIZE or ly < 0 or ly >= HEIGHT or lz < 0 or lz >= SIZE:
		return -1
	return blocks[lx][ly][lz][sub]


func set_block(lx: int, ly: int, lz: int, sub: int, block_type: int) -> void:
	if lx >= 0 and lx < SIZE and ly >= 0 and ly < HEIGHT and lz >= 0 and lz < SIZE:
		blocks[lx][ly][lz][sub] = block_type
		if block_type != BlockTypes.Type.AIR and ly + 1 > max_height:
			max_height = ly + 1


func _get_neighbor(wx: int, wy: int, wz: int, sub: int) -> int:
	if wy < 0 or wy >= HEIGHT:
		return BlockTypes.Type.AIR
	var lx := wx - chunk_x * SIZE
	var lz := wz - chunk_z * SIZE
	if lx >= 0 and lx < SIZE and lz >= 0 and lz < SIZE:
		return blocks[lx][wy][lz][sub]
	if world_ref:
		return world_ref.get_block_at(wx, wy, wz, sub)
	return BlockTypes.Type.AIR


func generate_mesh() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var has_verts := false

	for lx in SIZE:
		var wx := chunk_x * SIZE + lx
		for lz in SIZE:
			var wz := chunk_z * SIZE + lz
			for ly in max_height:
				var ta: int = blocks[lx][ly][lz][0]
				var tb: int = blocks[lx][ly][lz][1]
				if ta != BlockTypes.Type.AIR:
					_add_prism_a(st, lx, ly, lz, wx, wz, ta)
					has_verts = true
				if tb != BlockTypes.Type.AIR:
					_add_prism_b(st, lx, ly, lz, wx, wz, tb)
					has_verts = true

	if not has_verts:
		_mesh_instance.mesh = null
		_collision_shape.shape = null
		return

	st.set_material(_material)
	var mesh := st.commit()
	_mesh_instance.mesh = mesh

	if mesh and mesh.get_surface_count() > 0:
		_collision_shape.shape = mesh.create_trimesh_shape()
	else:
		_collision_shape.shape = null


func _add_prism_a(st: SurfaceTool, lx: int, ly: int, lz: int, wx: int, wz: int, bt: int) -> void:
	# Type A: right-isosceles triangle (0,0)-(1,0)-(0,1) in XZ, right angle at (0,0)
	var fx := float(lx)
	var fy := float(ly)
	var fz := float(lz)

	var b0 := Vector3(fx, fy, fz)
	var b1 := Vector3(fx + 1, fy, fz)
	var b2 := Vector3(fx, fy, fz + 1)
	var t0 := Vector3(fx, fy + 1, fz)
	var t1 := Vector3(fx + 1, fy + 1, fz)
	var t2 := Vector3(fx, fy + 1, fz + 1)

	# Bottom: neighbor is A at (wx, ly-1, wz)
	if _get_neighbor(wx, ly - 1, wz, 0) == BlockTypes.Type.AIR:
		st.set_normal(Vector3(0, -1, 0))
		st.set_color(BlockTypes.get_color(bt, "bottom"))
		st.add_vertex(b0); st.add_vertex(b1); st.add_vertex(b2)

	# Top: neighbor is A at (wx, ly+1, wz)
	if _get_neighbor(wx, ly + 1, wz, 0) == BlockTypes.Type.AIR:
		st.set_normal(Vector3(0, 1, 0))
		st.set_color(BlockTypes.get_color(bt, "top"))
		st.add_vertex(t0); st.add_vertex(t2); st.add_vertex(t1)

	# South leg (z face, normal -Z): neighbor is B at (wx, ly, wz-1)
	if _get_neighbor(wx, ly, wz - 1, 1) == BlockTypes.Type.AIR:
		st.set_normal(Vector3(0, 0, -1))
		st.set_color(BlockTypes.get_color(bt, "side"))
		st.add_vertex(b0); st.add_vertex(t0); st.add_vertex(b1)
		st.add_vertex(b1); st.add_vertex(t0); st.add_vertex(t1)

	# West leg (x face, normal -X): neighbor is B at (wx-1, ly, wz)
	if _get_neighbor(wx - 1, ly, wz, 1) == BlockTypes.Type.AIR:
		st.set_normal(Vector3(-1, 0, 0))
		st.set_color(BlockTypes.get_color(bt, "side"))
		st.add_vertex(b0); st.add_vertex(b2); st.add_vertex(t0)
		st.add_vertex(b2); st.add_vertex(t2); st.add_vertex(t0)

	# Hypotenuse: neighbor is B at (wx, ly, wz)
	if _get_neighbor(wx, ly, wz, 1) == BlockTypes.Type.AIR:
		st.set_normal(HYPO_NORMAL_A)
		st.set_color(BlockTypes.get_color(bt, "side"))
		st.add_vertex(b1); st.add_vertex(t1); st.add_vertex(b2)
		st.add_vertex(t1); st.add_vertex(t2); st.add_vertex(b2)


func _add_prism_b(st: SurfaceTool, lx: int, ly: int, lz: int, wx: int, wz: int, bt: int) -> void:
	# Type B: right-isosceles triangle (1,0)-(1,1)-(0,1) in XZ, right angle at (1,1)
	var fx := float(lx)
	var fy := float(ly)
	var fz := float(lz)

	var b0 := Vector3(fx + 1, fy, fz)
	var b1 := Vector3(fx + 1, fy, fz + 1)
	var b2 := Vector3(fx, fy, fz + 1)
	var t0 := Vector3(fx + 1, fy + 1, fz)
	var t1 := Vector3(fx + 1, fy + 1, fz + 1)
	var t2 := Vector3(fx, fy + 1, fz + 1)

	# Bottom: neighbor is B at (wx, ly-1, wz)
	if _get_neighbor(wx, ly - 1, wz, 1) == BlockTypes.Type.AIR:
		st.set_normal(Vector3(0, -1, 0))
		st.set_color(BlockTypes.get_color(bt, "bottom"))
		st.add_vertex(b0); st.add_vertex(b1); st.add_vertex(b2)

	# Top: neighbor is B at (wx, ly+1, wz)
	if _get_neighbor(wx, ly + 1, wz, 1) == BlockTypes.Type.AIR:
		st.set_normal(Vector3(0, 1, 0))
		st.set_color(BlockTypes.get_color(bt, "top"))
		st.add_vertex(t0); st.add_vertex(t2); st.add_vertex(t1)

	# East leg (x face, normal +X): neighbor is A at (wx+1, ly, wz)
	if _get_neighbor(wx + 1, ly, wz, 0) == BlockTypes.Type.AIR:
		st.set_normal(Vector3(1, 0, 0))
		st.set_color(BlockTypes.get_color(bt, "side"))
		st.add_vertex(b0); st.add_vertex(t0); st.add_vertex(b1)
		st.add_vertex(b1); st.add_vertex(t0); st.add_vertex(t1)

	# North leg (z face, normal +Z): neighbor is A at (wx, ly, wz+1)
	if _get_neighbor(wx, ly, wz + 1, 0) == BlockTypes.Type.AIR:
		st.set_normal(Vector3(0, 0, 1))
		st.set_color(BlockTypes.get_color(bt, "side"))
		st.add_vertex(b2); st.add_vertex(b1); st.add_vertex(t2)
		st.add_vertex(b1); st.add_vertex(t1); st.add_vertex(t2)

	# Hypotenuse: neighbor is A at (wx, ly, wz)
	if _get_neighbor(wx, ly, wz, 0) == BlockTypes.Type.AIR:
		st.set_normal(HYPO_NORMAL_B)
		st.set_color(BlockTypes.get_color(bt, "side"))
		st.add_vertex(b0); st.add_vertex(b2); st.add_vertex(t0)
		st.add_vertex(b2); st.add_vertex(t2); st.add_vertex(t0)
