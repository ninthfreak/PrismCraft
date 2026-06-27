extends CharacterBody3D

const SPEED := 6.0
const JUMP_VELOCITY := 8.0
const MOUSE_SENSITIVITY := 0.002
const GRAVITY := 20.0

var world: Node
var current_block_type: int = BlockTypes.Type.GRASS

var _camera: Camera3D
var _ray: RayCast3D
var _block_label: Label


func _ready() -> void:
	_camera = $Head/Camera3D
	_ray = $Head/Camera3D/RayCast3D
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_setup_input()
	_setup_hud()
	# Wait for collision shapes to register before enabling physics
	set_physics_process(false)
	await get_tree().physics_frame
	await get_tree().physics_frame
	set_physics_process(true)


func _setup_input() -> void:
	_add_key_action("move_forward", KEY_W)
	_add_key_action("move_backward", KEY_S)
	_add_key_action("move_left", KEY_A)
	_add_key_action("move_right", KEY_D)
	_add_key_action("jump", KEY_SPACE)
	_add_mouse_action("break_block", MOUSE_BUTTON_LEFT)
	_add_mouse_action("place_block", MOUSE_BUTTON_RIGHT)


func _add_key_action(action_name: String, keycode: int) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
	var ev := InputEventKey.new()
	ev.physical_keycode = keycode
	InputMap.action_add_event(action_name, ev)


func _add_mouse_action(action_name: String, button: MouseButton) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	InputMap.action_add_event(action_name, ev)


func _setup_hud() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)

	# Crosshair
	var crosshair := Label.new()
	crosshair.text = "+"
	crosshair.add_theme_font_size_override("font_size", 32)
	crosshair.add_theme_color_override("font_color", Color.WHITE)
	crosshair.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	crosshair.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	crosshair.grow_horizontal = Control.GROW_DIRECTION_BOTH
	crosshair.grow_vertical = Control.GROW_DIRECTION_BOTH
	canvas.add_child(crosshair)

	# Block type label
	_block_label = Label.new()
	_block_label.add_theme_font_size_override("font_size", 20)
	_block_label.add_theme_color_override("font_color", Color.WHITE)
	_block_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_block_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_block_label.offset_top = -60
	canvas.add_child(_block_label)

	# Controls help
	var help := Label.new()
	help.text = "WASD: Move | Mouse: Look | LMB: Break | RMB: Place | 1-6: Select block | Esc: Release mouse"
	help.add_theme_font_size_override("font_size", 14)
	help.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	help.offset_top = -30
	canvas.add_child(help)

	_update_block_label()


func _update_block_label() -> void:
	_block_label.text = "[" + BlockTypes.get_block_name(current_block_type) + "]"


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		_camera.rotate_x(-event.relative.y * MOUSE_SENSITIVITY)
		_camera.rotation.x = clampf(_camera.rotation.x, -PI * 0.49, PI * 0.49)

	if event is InputEventMouseButton and event.pressed:
		if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
			return

	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_ESCAPE:
				Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
			KEY_1:
				current_block_type = BlockTypes.Type.GRASS; _update_block_label()
			KEY_2:
				current_block_type = BlockTypes.Type.DIRT; _update_block_label()
			KEY_3:
				current_block_type = BlockTypes.Type.STONE; _update_block_label()
			KEY_4:
				current_block_type = BlockTypes.Type.SAND; _update_block_label()
			KEY_5:
				current_block_type = BlockTypes.Type.WOOD; _update_block_label()
			KEY_6:
				current_block_type = BlockTypes.Type.LEAVES; _update_block_label()


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	var input_dir := Vector2.ZERO
	input_dir.x = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	input_dir.y = Input.get_action_strength("move_backward") - Input.get_action_strength("move_forward")

	var direction := (global_transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if direction:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED * 2)
		velocity.z = move_toward(velocity.z, 0, SPEED * 2)

	move_and_slide()

	if Input.is_action_just_pressed("break_block"):
		_break_block()
	if Input.is_action_just_pressed("place_block"):
		_place_block()


func _break_block() -> void:
	if not _ray.is_colliding() or not world:
		return
	var hit_pos := _ray.get_collision_point()
	var hit_normal := _ray.get_collision_normal()
	var check_pos := hit_pos - hit_normal * 0.1
	var bx := floori(check_pos.x)
	var by := floori(check_pos.y)
	var bz := floori(check_pos.z)
	var frac_x := check_pos.x - bx
	var frac_z := check_pos.z - bz
	var sub := 0 if (frac_x + frac_z < 1.0) else 1
	world.set_block_at(bx, by, bz, sub, BlockTypes.Type.AIR)


func _place_block() -> void:
	if not _ray.is_colliding() or not world:
		return
	var hit_pos := _ray.get_collision_point()
	var hit_normal := _ray.get_collision_normal()
	var check_pos := hit_pos - hit_normal * 0.1
	var bx := floori(check_pos.x)
	var by := floori(check_pos.y)
	var bz := floori(check_pos.z)
	var frac_x := check_pos.x - bx
	var frac_z := check_pos.z - bz
	var hit_sub := 0 if (frac_x + frac_z < 1.0) else 1

	var target := _get_placement_target(bx, by, bz, hit_sub, hit_normal)
	if target.w < 0:
		return

	# Don't place inside the player
	var pp := global_position
	if target.x == floori(pp.x) and target.z == floori(pp.z):
		if target.y >= floori(pp.y) - 1 and target.y <= floori(pp.y) + 1:
			return

	world.set_block_at(target.x, target.y, target.z, target.w, current_block_type)


func _get_placement_target(bx: int, by: int, bz: int, sub: int, normal: Vector3) -> Vector4i:
	# Y-dominant face
	if absf(normal.y) > 0.5:
		if normal.y > 0:
			return Vector4i(bx, by + 1, bz, sub)
		else:
			return Vector4i(bx, by - 1, bz, sub)

	# Hypotenuse face (both X and Z are significant)
	var is_hypo := absf(normal.x) > 0.3 and absf(normal.z) > 0.3

	if sub == 0: # Type A hit
		if is_hypo:
			return Vector4i(bx, by, bz, 1)
		elif absf(normal.z) > absf(normal.x): # South
			return Vector4i(bx, by, bz - 1, 1)
		else: # West
			return Vector4i(bx - 1, by, bz, 1)
	else: # Type B hit
		if is_hypo:
			return Vector4i(bx, by, bz, 0)
		elif absf(normal.x) > absf(normal.z): # East
			return Vector4i(bx + 1, by, bz, 0)
		else: # North
			return Vector4i(bx, by, bz + 1, 0)

	return Vector4i(0, 0, 0, -1) # Invalid
