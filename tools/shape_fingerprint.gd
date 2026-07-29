extends SceneTree

# Prints a hash of every shape's pure geometry — cell type and orientation, with
# colour deliberately excluded.
#
#   godot --headless --script res://tools/shape_fingerprint.gd
#
# Stripping colour out of the shape builders touches the same lines that place
# the cells, so "the shape still exports and still passes validation" is not
# evidence the geometry survived: a builder that quietly places a different cell
# produces a different-but-consistent model, and the volume check would agree
# with it. Capture this before the rewrite and diff it after; it must not move.

const GX := 32
const GY := 32
const GZ := 32

const LAYOUTS := ["uniform", "capped", "net", "octagon_full", "octagon_half",
	"ramp", "gable", "diagwall", "diamond", "chamfered", "cross", "panel",
	"slab_quarter", "slab_half", "stairs_4", "pipe_quarter"]


func _initialize() -> void:
	for layout in LAYOUTS:
		print("%-14s %s" % [layout, _fingerprint(layout)])
	quit()


func _fingerprint(layout: String) -> String:
	var cells: Array = _build(layout)
	# Pack type and orientation only. A plain running hash is enough — this is
	# compared against itself, not stored.
	var h1 := 1469598103
	var h2 := 0
	var solid := 0
	var prism := 0
	for x in range(GX):
		for y in range(GY):
			for z in range(GZ):
				var c: Array = cells[x][y][z]
				var t: int = c[0]
				var o: int = c[1] if t == CellTypes.Type.PRISM else 0
				if t == CellTypes.Type.SOLID: solid += 1
				elif t == CellTypes.Type.PRISM: prism += 1
				var v := t * 13 + o * 131
				h1 = ((h1 * 16777619) ^ v) & 0x7FFFFFFF
				h2 = (h2 + v * (x * 7 + y * 31 + z * 97 + 1)) & 0x7FFFFFFF
	return "solid=%-6d prism=%-5d hash=%08x/%08x" % [solid, prism, h1, h2]


func _build(layout: String) -> Array:
	var dims := BlockImporter.atlas_dims(layout, GX, GY)
	var img := Image.create_empty(dims.x, dims.y, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.58, 0.58, 0.58, 1.0))
	return BlockImporter.build_cells(layout, img, GX, GY, GZ, BlockImporter.default_opt(layout))
