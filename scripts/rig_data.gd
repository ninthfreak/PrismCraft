class_name RigData
extends RefCounted

# Shared rigging state: the humanoid skeleton plus per-voxel bone assignment.
# Used by the editor's Rig Paint tool (to edit) and the Rig window (to preview /
# export). Auto-fit seeds everything; the user paints corrections on top.
#
# Two per-voxel arrays, both indexed (x*gy + y)*gz + z:
#   owner[v]   = bone that this voxel rigidly belongs to (-1 = empty)
#   overlap[v] = bone this voxel is ALSO duplicated into as a joint sleeve
#                (-1 = none). Independent of owner.

# ─── Humanoid template. Left/Right are the CHARACTER's own sides (anatomical),
# matching Mesh2Motion / Mixamo / Godot's humanoid profile. ───
const JOINT_NAMES := [
	"hips", "spine", "chest", "neck", "head",
	"L_shoulder", "L_elbow", "L_wrist",
	"R_shoulder", "R_elbow", "R_wrist",
	"L_hip", "L_knee", "L_ankle",
	"R_hip", "R_knee", "R_ankle",
]
const JOINT_PARENT := [
	-1, 0, 1, 2, 3,
	2, 5, 6,
	2, 8, 9,
	0, 11, 12,
	0, 14, 15,
]

var gx := 0
var gy := 0
var gz := 0
var solid: PackedByteArray = PackedByteArray()
var joint_pos: Array = []            # Array[Vector3] (voxel units)
var owner: PackedInt32Array = PackedInt32Array()
var overlap: PackedInt32Array = PackedInt32Array()
var fitted := false

func njoints() -> int:
	return JOINT_NAMES.size()

func idx(x: int, y: int, z: int) -> int:
	return (x * gy + y) * gz + z

func is_solid(x: int, y: int, z: int) -> bool:
	if x < 0 or x >= gx or y < 0 or y >= gy or z < 0 or z >= gz:
		return false
	return solid[idx(x, y, z)] != 0

# Build the solid mask from a cells array. Call whenever the model changes.
func set_grid(cells: Array, ngx: int, ngy: int, ngz: int) -> void:
	gx = ngx; gy = ngy; gz = ngz
	solid = PackedByteArray()
	solid.resize(gx * gy * gz)
	for x in range(gx):
		for y in range(gy):
			for z in range(gz):
				if cells[x][y][z][0] != CellTypes.Type.EMPTY:
					solid[idx(x, y, z)] = 1
	if joint_pos.is_empty():
		joint_pos.resize(njoints())
		for j in range(njoints()):
			joint_pos[j] = Vector3.ZERO

# ─── Auto-fit: detect the skeleton from the solid shape (T-pose assumed) ───

func auto_fit() -> void:
	if gx == 0:
		return
	var width := PackedInt32Array(); width.resize(gy)
	var xmn := PackedInt32Array(); xmn.resize(gy)
	var xmx := PackedInt32Array(); xmx.resize(gy)
	var runs := PackedInt32Array(); runs.resize(gy)
	var ylo := gy; var yhi := -1
	var zsum := 0.0; var zcount := 0
	for y in range(gy):
		var lo := gx; var hi := -1; var r := 0; var prev := false
		for x in range(gx):
			var occ := false
			var base := (x * gy + y) * gz
			for z in range(gz):
				if solid[base + z] != 0:
					occ = true
					zsum += z; zcount += 1
			if occ:
				lo = mini(lo, x); hi = maxi(hi, x)
				if not prev:
					r += 1
			prev = occ
		if hi >= 0:
			ylo = mini(ylo, y); yhi = maxi(yhi, y)
			width[y] = hi - lo + 1; xmn[y] = lo; xmx[y] = hi; runs[y] = r
	if yhi < 0:
		return
	var cz := zsum / maxf(zcount, 1)

	var shoulder_y := ylo
	for y in range(ylo, yhi + 1):
		if width[y] > width[shoulder_y]:
			shoulder_y = y
	var arm_lo := xmn[shoulder_y]
	var arm_hi := xmx[shoulder_y]

	var neck_y := shoulder_y
	var neck_w := 1 << 30
	for y in range(shoulder_y + 1, yhi + 1):
		if width[y] > 0 and width[y] < neck_w:
			neck_w = width[y]; neck_y = y

	var hx := 0.0; var hy := 0.0; var hz := 0.0; var hn := 0
	for x in range(gx):
		for y in range(neck_y + 1, gy):
			var base := (x * gy + y) * gz
			for z in range(gz):
				if solid[base + z] != 0:
					hx += x; hy += y; hz += z; hn += 1
	var head_cx := (hx / maxf(hn, 1)) if hn > 0 else float(arm_lo + arm_hi) * 0.5
	var head_cy := (hy / maxf(hn, 1)) if hn > 0 else float(neck_y + 4)
	var head_cz := (hz / maxf(hn, 1)) if hn > 0 else cz

	var hips_y := ylo + 1
	for y in range(ylo, shoulder_y):
		if runs[y] >= 2:
			hips_y = y
	hips_y = mini(hips_y + 1, shoulder_y - 1)

	var spine_y := int(round((hips_y + shoulder_y) * 0.5))
	var seed_x := int(float(xmn[spine_y] + xmx[spine_y]) * 0.5) if width[spine_y] > 0 else gx / 2
	var trange := _central_x_run(spine_y, seed_x)
	var torso_lo := float(trange.x)
	var torso_hi := float(trange.y)
	var torso_cx := (torso_lo + torso_hi) * 0.5

	var leg_y := int(round((ylo + hips_y) * 0.5))
	var legs := _two_runs(leg_y)
	var lo_leg := legs.x     # lower-x leg  (character's RIGHT when facing viewer)
	var hi_leg := legs.y     # higher-x leg (character's LEFT)

	var ankle_y := float(ylo + 1)
	var knee_y := (ankle_y + hips_y) * 0.5

	joint_pos.resize(njoints())
	joint_pos[0]  = Vector3(torso_cx, hips_y, cz)                        # hips
	joint_pos[1]  = Vector3(torso_cx, spine_y, cz)                       # spine
	joint_pos[2]  = Vector3(torso_cx, shoulder_y, cz)                    # chest
	joint_pos[3]  = Vector3(torso_cx, neck_y, cz)                        # neck
	joint_pos[4]  = Vector3(head_cx, head_cy, head_cz)                   # head
	# Anatomical L/R: the higher-x side is the character's LEFT, lower-x is RIGHT.
	joint_pos[5]  = Vector3(torso_hi, shoulder_y, cz)                    # L_shoulder
	joint_pos[6]  = Vector3((torso_hi + arm_hi) * 0.5, shoulder_y, cz)   # L_elbow
	joint_pos[7]  = Vector3(arm_hi, shoulder_y, cz)                      # L_wrist
	joint_pos[8]  = Vector3(torso_lo, shoulder_y, cz)                    # R_shoulder
	joint_pos[9]  = Vector3((torso_lo + arm_lo) * 0.5, shoulder_y, cz)   # R_elbow
	joint_pos[10] = Vector3(arm_lo, shoulder_y, cz)                      # R_wrist
	joint_pos[11] = Vector3(hi_leg, hips_y, cz)                          # L_hip
	joint_pos[12] = Vector3(hi_leg, knee_y, cz)                          # L_knee
	joint_pos[13] = Vector3(hi_leg, ankle_y, cz)                         # L_ankle
	joint_pos[14] = Vector3(lo_leg, hips_y, cz)                          # R_hip
	joint_pos[15] = Vector3(lo_leg, knee_y, cz)                          # R_knee
	joint_pos[16] = Vector3(lo_leg, ankle_y, cz)                         # R_ankle

	compute_owner()
	# reset overlap to none
	overlap = PackedInt32Array()
	overlap.resize(gx * gy * gz)
	for i in range(overlap.size()):
		overlap[i] = -1
	fitted = true

func _solid_col_at(x: int, y: int) -> bool:
	if x < 0 or x >= gx or y < 0 or y >= gy:
		return false
	var base := (x * gy + y) * gz
	for z in range(gz):
		if solid[base + z] != 0:
			return true
	return false

func _central_x_run(y: int, seed_x: int) -> Vector2i:
	var lo := clampi(seed_x, 0, gx - 1)
	var hi := lo
	if not _solid_col_at(lo, y):
		var found := false
		for d in range(gx):
			if _solid_col_at(clampi(seed_x + d, 0, gx - 1), y):
				lo = clampi(seed_x + d, 0, gx - 1); hi = lo; found = true; break
			if _solid_col_at(clampi(seed_x - d, 0, gx - 1), y):
				lo = clampi(seed_x - d, 0, gx - 1); hi = lo; found = true; break
		if not found:
			return Vector2i(seed_x, seed_x)
	while lo - 1 >= 0 and _solid_col_at(lo - 1, y):
		lo -= 1
	while hi + 1 < gx and _solid_col_at(hi + 1, y):
		hi += 1
	return Vector2i(lo, hi)

func _two_runs(y: int) -> Vector2:
	var run_list: Array = []
	var s := -1
	for x in range(gx):
		var occ := _solid_col_at(x, y)
		if occ and s < 0:
			s = x
		elif not occ and s >= 0:
			run_list.append(Vector2(s, x - 1)); s = -1
	if s >= 0:
		run_list.append(Vector2(s, gx - 1))
	if run_list.size() >= 2:
		run_list.sort_custom(func(a, b): return (a.y - a.x) > (b.y - b.x))
		var a: Vector2 = run_list[0]; var b: Vector2 = run_list[1]
		var ca := (a.x + a.y) * 0.5; var cb := (b.x + b.y) * 0.5
		return Vector2(minf(ca, cb), maxf(ca, cb))
	var c := gx * 0.5
	return Vector2(c - gx * 0.12, c + gx * 0.12)

func _dist_point_seg(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var denom := ab.length_squared()
	var t := 0.0
	if denom > 0.0:
		t = clampf((p - a).dot(ab) / denom, 0.0, 1.0)
	return p.distance_to(a + ab * t)

# Assign each solid voxel to the nearest bone segment (owned by the segment's
# proximal / pivot joint). Overwrites owner; leaves overlap untouched.
func compute_owner() -> void:
	owner = PackedInt32Array()
	owner.resize(gx * gy * gz)
	var segs: Array = []
	for j in range(njoints()):
		var p: int = JOINT_PARENT[j]
		if p < 0:
			continue
		segs.append([p, joint_pos[p], joint_pos[j]])
	for x in range(gx):
		for y in range(gy):
			for z in range(gz):
				var i := (x * gy + y) * gz + z
				if solid[i] == 0:
					owner[i] = -1
					continue
				var pt := Vector3(x + 0.5, y + 0.5, z + 0.5)
				var best := INF
				var best_owner := 0
				for s in segs:
					var d: float = _dist_point_seg(pt, s[1], s[2])
					if d < best:
						best = d
						best_owner = s[0]
				owner[i] = best_owner

# ─── Painting (used by the editor Rig Paint tool) ───

# Brush 0 = assign this voxel to bone; 1 = clear its overlap tag AND (if it was
# tagged to this bone) revert; 2 = mark as overlap for bone.
func paint_owner(x: int, y: int, z: int, bone: int) -> void:
	if not is_solid(x, y, z):
		return
	owner[idx(x, y, z)] = bone

func paint_overlap(x: int, y: int, z: int, bone: int) -> void:
	if not is_solid(x, y, z):
		return
	overlap[idx(x, y, z)] = bone

func clear_overlap(x: int, y: int, z: int) -> void:
	if not is_solid(x, y, z):
		return
	overlap[idx(x, y, z)] = -1

func get_owner(x: int, y: int, z: int) -> int:
	if not is_solid(x, y, z):
		return -1
	return owner[idx(x, y, z)]

func get_overlap(x: int, y: int, z: int) -> int:
	if not is_solid(x, y, z):
		return -1
	return overlap[idx(x, y, z)]

# "Not part of this limb": reassign the voxel to the nearest bone that ISN'T
# `exclude`, and drop any overlap tag pointing at `exclude`.
func reassign_excluding(x: int, y: int, z: int, exclude: int) -> void:
	if not is_solid(x, y, z):
		return
	var pt := Vector3(x + 0.5, y + 0.5, z + 0.5)
	var best := INF
	var best_owner := -1
	for j in range(njoints()):
		var p: int = JOINT_PARENT[j]
		if p < 0 or p == exclude:
			continue
		var d := _dist_point_seg(pt, joint_pos[p], joint_pos[j])
		if d < best:
			best = d
			best_owner = p
	var i := idx(x, y, z)
	if best_owner >= 0:
		owner[i] = best_owner
	if overlap[i] == exclude:
		overlap[i] = -1
