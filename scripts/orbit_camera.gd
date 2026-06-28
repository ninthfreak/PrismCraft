extends Camera3D

var pivot := Vector3.ZERO
var distance := 15.0
var yaw := -PI / 4.0
var pitch := PI / 6.0

var _rmb_down := false
var _rmb_start := Vector2.ZERO
var _orbiting := false
var _panning := false

const DRAG_THRESHOLD := 4.0

func _ready():
	_update_transform()

func was_orbit_drag() -> bool:
	return _orbiting

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_RIGHT:
				if event.pressed:
					_rmb_down = true
					_rmb_start = event.position
					_orbiting = false
				else:
					_rmb_down = false
					_orbiting = false
			MOUSE_BUTTON_MIDDLE:
				_panning = event.pressed
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed:
					distance = max(1.0, distance * 0.85)
					_update_transform()
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					distance = min(40.0, distance / 0.85)
					_update_transform()

	if event is InputEventMouseMotion:
		if _rmb_down:
			if not _orbiting and event.position.distance_to(_rmb_start) > DRAG_THRESHOLD:
				_orbiting = true
			if _orbiting:
				yaw -= event.relative.x * 0.005
				pitch = clampf(pitch + event.relative.y * 0.005, -PI * 0.45, PI * 0.45)
				_update_transform()
		if _panning:
			var pan_speed := distance * 0.002
			pivot -= transform.basis.x * event.relative.x * pan_speed
			pivot += transform.basis.y * event.relative.y * pan_speed
			_update_transform()

func _update_transform() -> void:
	var offset := Vector3(
		sin(yaw) * cos(pitch),
		sin(pitch),
		cos(yaw) * cos(pitch)
	) * distance
	position = pivot + offset
	look_at(pivot, Vector3.UP)
