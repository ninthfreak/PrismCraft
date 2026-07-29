extends SceneTree

# Unit tests for CoplanarMerge on synthetic face lists with known answers.
#
#   godot --headless --script res://tools/test_merge.gd
#
# The merge is the one piece of genuinely new geometry code in the v2 gut, and
# it is the piece that cannot be checked by looking at a viewport: a hole, a
# sliver or a zero-area triangle all render as "fine" until the consumer trips
# over them. So it gets pinned down here instead, on inputs whose correct output
# is known by construction.

const S := 1.0 / 32.0

var _passed := 0
var _failed := 0


func _initialize() -> void:
	_test_strip_collapses()
	_test_grid_collapses()
	_test_gap_is_respected()
	_test_distinct_planes_never_merge()
	_test_opposite_normals_never_merge()
	_test_distinct_colors_never_merge()
	_test_diagonal_plane_collapses()
	_test_triangles_pass_through()
	_test_single_face_untouched()
	_test_l_shape_makes_no_hole()
	_test_area_is_conserved()
	_test_winding_survives()
	_test_no_degenerate_output()

	print("")
	if _failed == 0:
		print("PASS  %d/%d merge tests" % [_passed, _passed])
	else:
		print("FAIL  %d of %d merge tests failed" % [_failed, _passed + _failed])
	quit(1 if _failed > 0 else 0)


# ── cases ────────────────────────────────────────────────────────────────────

# A run of 32 coplanar quads is the ramp-slope case the pass exists for.
func _test_strip_collapses() -> void:
	var faces: Array = []
	for i in range(32):
		faces.append(_quad_xy(i * S, (i + 1) * S, 0.0, 1.0, 0.5))
	var out := CoplanarMerge.merge(faces)
	_eq("32-quad strip collapses to 1", out.size(), 1)
	_close("strip keeps its area", _total_area(out), _total_area(faces))


func _test_grid_collapses() -> void:
	var faces: Array = []
	for i in range(4):
		for j in range(4):
			faces.append(_quad_xy(i * S, (i + 1) * S, j * S, (j + 1) * S, 0.5))
	var out := CoplanarMerge.merge(faces)
	_eq("4x4 tiling collapses to 1", out.size(), 1)
	_close("tiling keeps its area", _total_area(out), _total_area(faces))


# Two runs with a hole between them are two surfaces, not one.
func _test_gap_is_respected() -> void:
	var faces: Array = []
	for i in [0, 1, 2, 5, 6]:
		faces.append(_quad_xy(i * S, (i + 1) * S, 0.0, 1.0, 0.5))
	var out := CoplanarMerge.merge(faces)
	_eq("a gap splits a strip into 2", out.size(), 2)
	_close("gapped strip keeps its area", _total_area(out), _total_area(faces))


# The tolerance must not be so loose that it welds two genuinely different
# planes together — that would silently move geometry.
func _test_distinct_planes_never_merge() -> void:
	var a := _quad_xy(0.0, S, 0.0, S, 0.5)
	var b := _quad_xy(S, 2.0 * S, 0.0, S, 0.5 + 0.001)
	var out := CoplanarMerge.merge([a, b])
	_eq("planes 0.001 apart stay separate", out.size(), 2)

	var c := _quad_xy(0.0, S, 0.0, S, 0.5)
	var d: Array = [0, Vector3(0, 0, 1).rotated(Vector3(1, 0, 0), 0.02).normalized(),
		[Vector3(S, 0, 0.5), Vector3(2.0 * S, 0, 0.5), Vector3(2.0 * S, S, 0.5), Vector3(S, S, 0.5)]]
	var out2 := CoplanarMerge.merge([c, d])
	_eq("tilted normals stay separate", out2.size(), 2)


# Back-to-back surfaces share a plane but face opposite ways.
func _test_opposite_normals_never_merge() -> void:
	var a := _quad_xy(0.0, S, 0.0, S, 0.5)
	var b := _quad_xy(S, 2.0 * S, 0.0, S, 0.5)
	b[1] = Vector3(0, 0, -1)
	var out := CoplanarMerge.merge([a, b])
	_eq("opposed normals stay separate", out.size(), 2)


func _test_distinct_colors_never_merge() -> void:
	var a := _quad_xy(0.0, S, 0.0, S, 0.5)
	var b := _quad_xy(S, 2.0 * S, 0.0, S, 0.5)
	b[0] = 999
	var out := CoplanarMerge.merge([a, b])
	_eq("distinct colours stay separate", out.size(), 2)


# The real prize: a 45deg slope, which the greedy mesher can never touch.
func _test_diagonal_plane_collapses() -> void:
	var n := Vector3(0, -1, 1).normalized()
	var faces: Array = []
	for i in range(32):
		var y0 := i * S
		var y1 := (i + 1) * S
		faces.append([0, n, [
			Vector3(-0.5, y0, y0), Vector3(0.5, y0, y0),
			Vector3(0.5, y1, y1), Vector3(-0.5, y1, y1)]])
	var out := CoplanarMerge.merge(faces)
	_eq("45deg slope collapses to 1", out.size(), 1)
	_close("slope keeps its area", _total_area(out), _total_area(faces))


# Prism caps are triangles. The pass must not mangle them.
func _test_triangles_pass_through() -> void:
	var t1: Array = [0, Vector3(0, 0, 1), [Vector3(0, 0, 0.5), Vector3(S, 0, 0.5), Vector3(0, S, 0.5)]]
	var t2: Array = [0, Vector3(0, 0, 1), [Vector3(S, S, 0.5), Vector3(0, S, 0.5), Vector3(S, 0, 0.5)]]
	var out := CoplanarMerge.merge([t1, t2])
	_eq("coplanar triangles pass through", out.size(), 2)
	_close("triangles keep their area", _total_area(out), _total_area([t1, t2]))


func _test_single_face_untouched() -> void:
	var a := _quad_xy(0.0, S, 0.0, S, 0.5)
	var out := CoplanarMerge.merge([a])
	_eq("a lone face is returned as-is", out.size(), 1)


# An L cannot become one rectangle. It must come back as 2 pieces covering the
# same area — never 1 (which would invent geometry) and never a ring.
func _test_l_shape_makes_no_hole() -> void:
	var faces: Array = [
		_quad_xy(0.0, S, 0.0, S, 0.5),
		_quad_xy(S, 2.0 * S, 0.0, S, 0.5),
		_quad_xy(0.0, S, S, 2.0 * S, 0.5),
	]
	var out := CoplanarMerge.merge(faces)
	_eq("an L merges to 2 rectangles", out.size(), 2)
	_close("the L keeps its area", _total_area(out), _total_area(faces))


func _test_area_is_conserved() -> void:
	var faces: Array = []
	for i in range(8):
		for j in range(3):
			faces.append(_quad_xy(i * S, (i + 1) * S, j * S, (j + 1) * S, 0.25))
	for i in range(5):
		faces.append(_quad_xy(i * S, (i + 1) * S, 0.0, S, -0.25))
	var out := CoplanarMerge.merge(faces)
	_close("area survives a mixed-plane merge", _total_area(out), _total_area(faces))


func _test_winding_survives() -> void:
	var faces: Array = []
	for i in range(4):
		faces.append(_quad_xy(i * S, (i + 1) * S, 0.0, S, 0.5))
	var out := CoplanarMerge.merge(faces)
	var ok := true
	for f in out:
		var v: Array = f[2]
		var cross: Vector3 = (v[1] - v[0]).cross(v[2] - v[0])
		if cross.normalized().dot((f[1] as Vector3).normalized()) < 0.99:
			ok = false
	_true("merged quads stay wound with their normal", ok)


func _test_no_degenerate_output() -> void:
	var faces: Array = []
	for i in range(16):
		faces.append(_quad_xy(i * S, (i + 1) * S, 0.0, S, 0.5))
	for i in range(16):
		faces.append(_quad_xy(i * S, (i + 1) * S, S, 2.0 * S, 0.5))
	var out := CoplanarMerge.merge(faces)
	_eq("two stacked strips collapse to 1", out.size(), 1)
	var ok := true
	for f in out:
		if _area(f[2]) < 1e-9:
			ok = false
	_true("merge emits no zero-area faces", ok)


# ── helpers ──────────────────────────────────────────────────────────────────

# Axis-aligned quad in the plane z = zpos, wound CCW seen from +Z.
func _quad_xy(x0: float, x1: float, y0: float, y1: float, zpos: float) -> Array:
	return [0, Vector3(0, 0, 1), [
		Vector3(x0, y0, zpos), Vector3(x1, y0, zpos),
		Vector3(x1, y1, zpos), Vector3(x0, y1, zpos)]]


func _area(verts: Array) -> float:
	var a := 0.0
	for i in range(1, verts.size() - 1):
		a += (verts[i] - verts[0]).cross(verts[i + 1] - verts[0]).length() * 0.5
	return a


func _total_area(faces: Array) -> float:
	var a := 0.0
	for f in faces:
		a += _area(f[2])
	return a


func _eq(label: String, got: int, want: int) -> void:
	if got == want:
		_passed += 1
		print("  ok    %s" % label)
	else:
		_failed += 1
		print("  FAIL  %s — got %d, want %d" % [label, got, want])


# Vector3 is single-precision in a stock Godot build (GDScript's float is not),
# so a 45deg plane accumulates ~1e-7 of drift over a 32-cell run that an
# axis-aligned plane does not — 1/32 is exact in binary, sqrt(2)/2 is not. The
# tolerance has to clear that noise while still failing loudly on a real defect:
# one dropped quad out of 32 is a 3% area change, ~3000x this bound.
func _close(label: String, got: float, want: float) -> void:
	if absf(got - want) <= 1e-5 * maxf(1.0, absf(want)):
		_passed += 1
		print("  ok    %s" % label)
	else:
		_failed += 1
		print("  FAIL  %s — got %.12f, want %.12f" % [label, got, want])


func _true(label: String, cond: bool) -> void:
	if cond:
		_passed += 1
		print("  ok    %s" % label)
	else:
		_failed += 1
		print("  FAIL  %s" % label)
