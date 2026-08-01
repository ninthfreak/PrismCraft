extends SceneTree
# Headless batch: build and export every library shape to .glb in one pass.
#
#   godot --headless --script res://scripts/batch_export.gd -- [out_dir]
#
# [out_dir]  where the .glb files go (default res://exports)
#
# Goes through the same ShapeBuilder and MeshExporter the editor uses, so batch
# and hand export cannot drift. Export is strict: a shape that violates the
# contract is reported and not written, and the run exits non-zero.

const GX := 32
const GY := 32
const GZ := 32
const CELL := 1.0 / 32.0

const SHAPES := ["cube", "ramp", "gable", "diagwall", "diamond", "chamfered",
	"cross", "panel", "slab_quarter", "slab_half", "stairs_4", "pipe_quarter",
	"octagon_full", "octagon_half"]


func _initialize() -> void:
	var uargs := OS.get_cmdline_user_args()
	var out_dir: String = uargs[0] if uargs.size() >= 1 else "res://exports"
	DirAccess.make_dir_recursive_absolute(out_dir)

	var failed := 0
	var total := 0
	for shape in SHAPES:
		# The consumer expects hyphens; the builders use underscores internally.
		var id: String = shape.replace("_", "-")
		var cells: Array = ShapeBuilder.build(shape, GX, GY, GZ)
		var path: String = out_dir.path_join(id + ".glb")
		var tris: int = MeshExporter.export_glb(path, cells, GX, GY, GZ, CELL)
		if tris < 0:
			failed += 1
			printerr("[batch] refused %s:" % id)
			for e in MeshExporter.last_export_errors:
				printerr("          %s" % e)
		elif tris == 0:
			failed += 1
			printerr("[batch] failed to write %s" % path)
		else:
			total += tris
			print("[batch] %-14s %4d tris" % [id, tris])

	print("[batch] %d shapes, %d triangles, %d failed" % [SHAPES.size(), total, failed])
	quit(1 if failed > 0 else 0)
