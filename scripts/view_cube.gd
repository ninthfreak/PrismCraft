extends Control

signal view_changed(yaw: float, pitch: float)

const CUBE_SIZE := 80
const MARGIN := 10

var _cube_yaw := -PI / 4.0
var _cube_pitch := PI / 6.0
var _dragging := false
var _drag_start := Vector2.ZERO

const FACE_VIEWS := {
	"Front":  { "yaw": 0.0,       "pitch": 0.0 },
	"Back":   { "yaw": PI,        "pitch": 0.0 },
	"Left":   { "yaw": -PI / 2.0, "pitch": 0.0 },
	"Right":  { "yaw": PI / 2.0,  "pitch": 0.0 },
	"Top":    { "yaw": 0.0,       "pitch": PI * 0.449 },
	"Bottom": { "yaw": 0.0,       "pitch": -PI * 0.449 },
}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS

func set_orientation(yaw: float, pitch: float) -> void:
	_cube_yaw = yaw
	_cube_pitch = pitch
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_dragging = true
			_drag_start = event.position
			accept_event()
		else:
			if _dragging and event.position.distance_to(_drag_start) < 5.0:
				_handle_face_click(event.position)
			_dragging = false
			accept_event()

	if event is InputEventMouseMotion and _dragging:
		_cube_yaw -= event.relative.x * 0.01
		_cube_pitch = clampf(_cube_pitch - event.relative.y * 0.01, -PI * 0.45, PI * 0.45)
		view_changed.emit(_cube_yaw, _cube_pitch)
		queue_redraw()
		accept_event()

func _handle_face_click(pos: Vector2) -> void:
	var center := size / 2.0
	var half := CUBE_SIZE * 0.35
	var faces := _get_projected_faces()
	# Check faces front-to-back (last drawn = on top)
	for i in range(faces.size() - 1, -1, -1):
		var face: Dictionary = faces[i]
		var verts: Array = face["screen_verts"]
		if _point_in_quad(pos, verts):
			var view: Dictionary = FACE_VIEWS[face["name"]]
			_cube_yaw = view["yaw"]
			_cube_pitch = view["pitch"]
			view_changed.emit(_cube_yaw, _cube_pitch)
			queue_redraw()
			return

func _point_in_quad(p: Vector2, verts: Array) -> bool:
	return _point_in_tri(p, verts[0], verts[1], verts[2]) or _point_in_tri(p, verts[0], verts[2], verts[3])

func _point_in_tri(p: Vector2, a: Vector2, b: Vector2, c: Vector2) -> bool:
	var d1 := _sign_2d(p, a, b)
	var d2 := _sign_2d(p, b, c)
	var d3 := _sign_2d(p, c, a)
	var has_neg := (d1 < 0) or (d2 < 0) or (d3 < 0)
	var has_pos := (d1 > 0) or (d2 > 0) or (d3 > 0)
	return not (has_neg and has_pos)

func _sign_2d(p1: Vector2, p2: Vector2, p3: Vector2) -> float:
	return (p1.x - p3.x) * (p2.y - p3.y) - (p2.x - p3.x) * (p1.y - p3.y)

func _project_point(v: Vector3) -> Vector2:
	var center := size / 2.0
	var s := CUBE_SIZE * 0.4
	var cy := cos(_cube_yaw)
	var sy := sin(_cube_yaw)
	var cp := cos(_cube_pitch)
	var sp := sin(_cube_pitch)
	var rx := v.x * cy + v.z * sy
	var rz := -v.x * sy + v.z * cy
	var ry := v.y * cp - rz * sp
	var rz2 := v.y * sp + rz * cp
	return center + Vector2(rx, -ry) * s

func _get_cube_verts() -> Array[Vector3]:
	return [
		Vector3(-1, -1, -1), Vector3( 1, -1, -1), Vector3( 1, -1,  1), Vector3(-1, -1,  1),
		Vector3(-1,  1, -1), Vector3( 1,  1, -1), Vector3( 1,  1,  1), Vector3(-1,  1,  1),
	]

func _get_projected_faces() -> Array:
	var verts := _get_cube_verts()
	var sv: Array = []
	for v in verts:
		sv.append(_project_point(v))

	var face_defs := [
		{ "name": "Front",  "indices": [3, 2, 6, 7], "normal": Vector3(0, 0, 1) },
		{ "name": "Back",   "indices": [1, 0, 4, 5], "normal": Vector3(0, 0, -1) },
		{ "name": "Left",   "indices": [0, 3, 7, 4], "normal": Vector3(-1, 0, 0) },
		{ "name": "Right",  "indices": [2, 1, 5, 6], "normal": Vector3(1, 0, 0) },
		{ "name": "Top",    "indices": [4, 5, 6, 7], "normal": Vector3(0, 1, 0) },
		{ "name": "Bottom", "indices": [3, 2, 1, 0], "normal": Vector3(0, -1, 0) },
	]

	var faces: Array = []
	for fd in face_defs:
		var n: Vector3 = fd["normal"]
		var cy := cos(_cube_yaw)
		var sy := sin(_cube_yaw)
		var cp := cos(_cube_pitch)
		var sp := sin(_cube_pitch)
		var rx := n.x * cy + n.z * sy
		var rz := -n.x * sy + n.z * cy
		var rz2 := n.y * sp + rz * cp
		if rz2 <= 0:
			continue
		var idxs: Array = fd["indices"]
		faces.append({
			"name": fd["name"],
			"screen_verts": [sv[idxs[0]], sv[idxs[1]], sv[idxs[2]], sv[idxs[3]]],
			"depth": rz2,
		})

	faces.sort_custom(func(a: Dictionary, b: Dictionary): return a["depth"] < b["depth"])
	return faces

func _draw() -> void:
	# Background circle
	var center := size / 2.0
	draw_circle(center, CUBE_SIZE * 0.48, Color(0.1, 0.1, 0.12, 0.5))

	var faces := _get_projected_faces()

	var face_colors := {
		"Front":  Color(0.25, 0.45, 0.7, 0.85),
		"Back":   Color(0.25, 0.45, 0.7, 0.6),
		"Left":   Color(0.3, 0.55, 0.35, 0.85),
		"Right":  Color(0.3, 0.55, 0.35, 0.6),
		"Top":    Color(0.65, 0.55, 0.3, 0.85),
		"Bottom": Color(0.65, 0.55, 0.3, 0.6),
	}

	var edge_color := Color(0.8, 0.8, 0.8, 0.6)
	var font := ThemeDB.fallback_font

	for face in faces:
		var verts: Array = face["screen_verts"]
		var color: Color = face_colors.get(face["name"], Color(0.3, 0.3, 0.3, 0.7))
		var points := PackedVector2Array([verts[0], verts[1], verts[2], verts[3]])
		var colors := PackedColorArray([color, color, color, color])
		draw_polygon(points, colors)
		for i in range(4):
			draw_line(verts[i], verts[(i + 1) % 4], edge_color, 1.0)

		# Face label
		var cx2: Vector2 = (verts[0] + verts[1] + verts[2] + verts[3]) / 4.0
		var label: String = face["name"]
		var fsize := 11
		var text_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, fsize)
		draw_string(font, cx2 - text_size / 2.0 + Vector2(0, text_size.y * 0.35), label, HORIZONTAL_ALIGNMENT_CENTER, -1, fsize, Color.WHITE)

	# Axis indicators
	var axis_len := CUBE_SIZE * 0.35
	var origin := center + Vector2(0, CUBE_SIZE * 0.45)
	var x_end := _project_point(Vector3(1.5, 0, 0)) - center + origin
	var y_end := _project_point(Vector3(0, 1.5, 0)) - center + origin
	var z_end := _project_point(Vector3(0, 0, 1.5)) - center + origin
	draw_line(origin, x_end, Color.RED, 2.0)
	draw_line(origin, y_end, Color.GREEN, 2.0)
	draw_line(origin, z_end, Color.BLUE, 2.0)
	var axis_font_size := 10
	draw_string(font, x_end + Vector2(2, -2), "X", HORIZONTAL_ALIGNMENT_LEFT, -1, axis_font_size, Color.RED)
	draw_string(font, y_end + Vector2(2, -2), "Y", HORIZONTAL_ALIGNMENT_LEFT, -1, axis_font_size, Color.GREEN)
	draw_string(font, z_end + Vector2(2, -2), "Z", HORIZONTAL_ALIGNMENT_LEFT, -1, axis_font_size, Color.BLUE)
