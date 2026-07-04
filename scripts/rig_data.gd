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
	# Rest pose is ARMS AT THE SIDES (matches the editor's characters), not a
	# T-pose. Read the silhouette from per-row run structure: neck pinch first
	# (so the head can be any size), then arm band (>=3 runs) / torso / legs.
	var width := PackedInt32Array(); width.resize(gy)
	var nrun := PackedInt32Array(); nrun.resize(gy)
	var ylo := gy; var yhi := -1
	var zsum := 0.0; var zcount := 0
	for y in range(gy):
		var r: Array = _runs_at(y)
		nrun[y] = r.size()
		if r.size() > 0:
			ylo = mini(ylo, y); yhi = maxi(yhi, y)
			var iv0: Vector2i = r[0]
			var ivn: Vector2i = r[r.size() - 1]
			width[y] = ivn.y - iv0.x + 1
			for x in range(gx):
				var base := (x * gy + y) * gz
				for z in range(gz):
					if solid[base + z] != 0:
						zsum += z; zcount += 1
	if yhi < 0:
		return
	var cz := zsum / maxf(zcount, 1)
	var H: int = maxi(yhi - ylo, 1)

	var neck_y := ylo + int(0.45 * H)
	var neck_w := 1 << 30
	for y in range(ylo + int(0.45 * H), yhi + 1):
		if width[y] > 0 and width[y] < neck_w:
			neck_w = width[y]; neck_y = y

	var hx := 0.0; var hy := 0.0; var hz := 0.0; var hn := 0
	for x in range(gx):
		for y in range(neck_y + 1, gy):
			var base := (x * gy + y) * gz
			for z in range(gz):
				if solid[base + z] != 0:
					hx += x; hy += y; hz += z; hn += 1
	var head_cx := (hx / hn) if hn > 0 else float(gx) * 0.5
	var head_cy := (hy / hn) if hn > 0 else float(neck_y + 4)
	var head_cz := (hz / hn) if hn > 0 else cz

	# arm band: longest contiguous stretch below the neck that splits into >=3
	# runs (arm | torso | arm); its bottom row = the wrists.
	var arm_top := -1; var arm_bot := -1
	var seg_start := -1; var seg_best := 0
	for y in range(ylo, neck_y + 1):
		var three := y < neck_y and nrun[y] >= 3
		if three and seg_start < 0:
			seg_start = y
		if not three and seg_start >= 0:
			if y - seg_start > seg_best:
				seg_best = y - seg_start; arm_bot = seg_start; arm_top = y - 1
			seg_start = -1

	var torso_lo: float; var torso_hi: float
	if arm_top >= 0:
		var rr: Array = _runs_at((arm_top + arm_bot) / 2)
		var sx := 0.0; var sc := 0
		for iv in rr:
			var w: int = iv.y - iv.x + 1
			sx += float(iv.x + iv.y) * 0.5 * w; sc += w
		var comx := sx / maxf(sc, 1)
		var bi: Vector2i = rr[0]
		for iv in rr:
			if absf(float(iv.x + iv.y) * 0.5 - comx) < absf(float(bi.x + bi.y) * 0.5 - comx):
				bi = iv
		torso_lo = bi.x; torso_hi = bi.y
	else:
		var tr := _central_x_run((ylo + neck_y) / 2, gx / 2)
		torso_lo = tr.x; torso_hi = tr.y
	var torso_cx := (torso_lo + torso_hi) * 0.5

	# shoulders: widest single-run row between the arm band and the neck.
	var shoulder_y := arm_top if arm_top >= 0 else neck_y - 1
	var sw := -1
	for y in range((arm_top if arm_top >= 0 else ylo) + 1, neck_y + 1):
		if nrun[y] == 1 and width[y] > sw:
			sw = width[y]; shoulder_y = y
	if sw < 0:
		for y in range(ylo, neck_y):
			if width[y] > sw:
				sw = width[y]; shoulder_y = y

	# legs: lowest contiguous 2-run band; hips at its top.
	var leg_top := ylo - 1
	for y in range(ylo, yhi + 1):
		if nrun[y] == 2:
			leg_top = y
		else:
			break
	var hips_y := clampi((leg_top if leg_top >= ylo else ylo) + 1, ylo + 1, maxi(ylo + 2, shoulder_y - 1))
	var lo_leg: float; var hi_leg: float
	if leg_top >= ylo:
		var legs := _two_runs((ylo + leg_top) / 2)
		lo_leg = legs.x; hi_leg = legs.y     # low x = char RIGHT, high x = char LEFT
	else:
		lo_leg = torso_cx - float(gx) * 0.06; hi_leg = torso_cx + float(gx) * 0.06

	# arm columns: run centres outside the torso across the band (median).
	var lxs: Array = []; var rxs: Array = []
	if arm_top >= 0:
		for y in range(arm_bot, arm_top + 1):
			for iv in _runs_at(y):
				var c := float(iv.x + iv.y) * 0.5
				if float(iv.y) < torso_lo:
					rxs.append(c)
				elif float(iv.x) > torso_hi:
					lxs.append(c)
	var l_arm_x := _median_f(lxs) if not lxs.is_empty() else torso_hi
	var r_arm_x := _median_f(rxs) if not rxs.is_empty() else torso_lo

	# Calibrate joint heights from the silhouette extremes to anatomical points.
	hips_y = clampi(hips_y + int(round(0.07 * (shoulder_y - hips_y))), hips_y, shoulder_y - 1)  # up off the crotch
	var arm_shoulder_y := int(round(shoulder_y + 0.55 * (neck_y - shoulder_y)))                # up toward the neck
	var arm_span := float(arm_shoulder_y - arm_bot) if arm_bot >= 0 else float(arm_shoulder_y - hips_y)
	var elbow_y := arm_shoulder_y - 0.53 * arm_span
	var wrist_y := arm_shoulder_y - 0.87 * arm_span                                            # inset up from the fingertip
	var leg_span := float(hips_y - ylo)
	var knee_y := hips_y - 0.47 * leg_span
	var ankle_y := float(ylo) + roundf(0.10 * leg_span)                                        # up off the toe
	var spine_y := int(round((hips_y + shoulder_y) * 0.5))

	joint_pos.resize(njoints())
	joint_pos[0]  = Vector3(torso_cx, hips_y, cz)                        # hips
	joint_pos[1]  = Vector3(torso_cx, spine_y, cz)                       # spine
	joint_pos[2]  = Vector3(torso_cx, shoulder_y, cz)                    # chest
	joint_pos[3]  = Vector3(torso_cx, neck_y, cz)                        # neck
	joint_pos[4]  = Vector3(head_cx, head_cy, head_cz)                   # head
	# Anatomical L/R: the higher-x side is the character's LEFT, lower-x is RIGHT.
	# Arms hang vertically at the sides: shoulder (top) -> elbow -> wrist (bottom).
	joint_pos[5]  = Vector3(l_arm_x, arm_shoulder_y, cz)                 # L_shoulder
	joint_pos[6]  = Vector3(l_arm_x, elbow_y, cz)                        # L_elbow
	joint_pos[7]  = Vector3(l_arm_x, wrist_y, cz)                        # L_wrist
	joint_pos[8]  = Vector3(r_arm_x, arm_shoulder_y, cz)                 # R_shoulder
	joint_pos[9]  = Vector3(r_arm_x, elbow_y, cz)                        # R_elbow
	joint_pos[10] = Vector3(r_arm_x, wrist_y, cz)                        # R_wrist
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

# Solid x-runs (front projection) at height y, as [lo, hi] intervals.
func _runs_at(y: int) -> Array:
	var res: Array = []
	var s := -1
	for x in range(gx):
		if _solid_col_at(x, y):
			if s < 0:
				s = x
		elif s >= 0:
			res.append(Vector2i(s, x - 1)); s = -1
	if s >= 0:
		res.append(Vector2i(s, gx - 1))
	return res

func _median_f(a: Array) -> float:
	if a.is_empty():
		return 0.0
	a.sort()
	return float(a[a.size() / 2])

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
				# Sample in the joints' index space (not voxel centres) so a
				# symmetric model rigs symmetrically — see the note in rig_view.gd.
				var pt := Vector3(x, y, z)
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
