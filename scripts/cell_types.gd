class_name CellTypes

enum Type {
	EMPTY = 0,
	SOLID = 1,
	PRISM = 2,
}

# Cell format: [type, orientation].
#
# A cell is geometry and nothing else. There is no colour, no per-face data and
# no alpha: the exported mesh carries positions and flat normals, and the
# consumer textures from world position in-shader. Orientation is meaningful
# only for PRISM (12 values: 3 axes x 4 corners); SOLID and EMPTY carry 0.

static func make_cell(cell_type: int, orientation: int) -> Array:
	return [cell_type, orientation]


static func empty_cell() -> Array:
	return [Type.EMPTY, 0]


# ─── Octagon geometry ────────────────────────────────────────────────────────
# Inset that makes all eight sides of the octagon equal, i.e. a regular octagon
# whose diagonal faces land on exactly 45 degrees and so are expressible as
# prism cells.
const OCTAGON_CHAMFER := 9

static func octagon_chamfer(footprint: int) -> int:
	return roundi((2.0 - sqrt(2.0)) / 2.0 * footprint)


# ─── Prism occlusion ─────────────────────────────────────────────────────────
# True if a prism of this orientation fully covers the cube face with outward
# normal n — that is, n is one of its two legs.
#
# A prism covers exactly two of its cell's six faces. The two caps it covers
# only halfway (a triangle), and the two "open" sides not at all, since the
# hypotenuse cuts across them. Only a leg can hide a neighbour's face, and only
# a leg can itself be hidden.
static func prism_covers_face(orientation: int, n: Vector3i) -> bool:
	var axis := orientation / 4
	var corner := orientation % 4
	var axis_n: Vector3i = [Vector3i(0, 1, 0), Vector3i(1, 0, 0), Vector3i(0, 0, 1)][axis]
	if n.x * axis_n.x + n.y * axis_n.y + n.z * axis_n.z != 0:
		return false  # a cap face: only half covered, so it occludes nothing
	var cu: int = [0, 1, 1, 0][corner]
	var cv: int = [0, 0, 1, 1][corner]
	var uax: Vector3i
	var vax: Vector3i
	match axis:
		0: uax = Vector3i(1, 0, 0); vax = Vector3i(0, 0, 1)
		1: uax = Vector3i(0, 1, 0); vax = Vector3i(0, 0, 1)
		_: uax = Vector3i(1, 0, 0); vax = Vector3i(0, 1, 0)
	var du := n.x * uax.x + n.y * uax.y + n.z * uax.z
	var dv := n.x * vax.x + n.y * vax.y + n.z * vax.z
	if du != 0:
		return (1 if du > 0 else 0) == cu
	if dv != 0:
		return (1 if dv > 0 else 0) == cv
	return false


static func get_orientation_name(orientation: int) -> String:
	var axis_names := ["Y", "X", "Z"]
	var corner_names := ["SW", "SE", "NE", "NW"]
	return axis_names[orientation / 4] + "-" + corner_names[orientation % 4]
