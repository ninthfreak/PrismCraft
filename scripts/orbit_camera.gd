extends Camera3D

var pivot := Vector3.ZERO
var distance := 15.0
var yaw := -PI / 4.0
var pitch := PI / 6.0
var _dragging := false

func _ready():
	_update_transform()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_RIGHT:
				_dragging = event.pressed
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed:
					distance = max(3.0, distance - 1.0)
					_update_transform()
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					distance = min(40.0, distance + 1.0)
					_update_transform()
	if event is InputEventMouseMotion and _dragging:
		yaw -= event.relative.x * 0.005
		pitch = clampf(pitch - event.relative.y * 0.005, -PI * 0.45, PI * 0.45)
		_update_transform()

func _update_transform() -> void:
	var offset := Vector3(
		sin(yaw) * cos(pitch),
		sin(pitch),
		cos(yaw) * cos(pitch)
	) * distance
	position = pivot + offset
	look_at(pivot, Vector3.UP)
