extends SceneTree

# Builds every shape in the library, exports it, and reports its triangle count
# against the budget.
#
#   godot --headless --script res://tools/export_shapes.gd -- <out_dir>

const GX := 32
const GY := 32
const GZ := 32
const CELL := 1.0 / 32.0
const BUDGET := 500

const LAYOUTS := ["cube", "octagon_full", "octagon_half",
	"ramp", "gable", "diagwall", "diamond", "chamfered", "cross", "panel",
	"slab_quarter", "slab_half", "stairs_4", "pipe_quarter"]


func _initialize() -> void:
	var uargs := OS.get_cmdline_user_args()
	var out_dir: String = uargs[0] if uargs.size() >= 1 else "user://exports"
	DirAccess.make_dir_recursive_absolute(out_dir)

	print("shape             tris   budget")
	print("---------------------------------")
	var total := 0
	var over := 0
	for layout in LAYOUTS:
		var cells: Array = ShapeBuilder.build(layout, GX, GY, GZ)
		var name := _export_name(layout)
		var tris: int = MeshExporter.export_glb(out_dir.path_join(name + ".glb"), cells, GX, GY, GZ, CELL)
		if tris < 0:
			print("%-14s  REFUSED  %s" % [name, MeshExporter.last_export_errors[0]])
			over += 1
			continue
		total += tris
		if tris > BUDGET:
			over += 1
		print("%-14s %6d %8s" % [name, tris, "ok" if tris <= BUDGET else "OVER"])
	print("")
	print("%d shapes, %d triangles total, %d over the %d budget" % [LAYOUTS.size(), total, over, BUDGET])
	quit(1 if over > 0 else 0)


# ShapeBuilder names shapes with underscores; the consumer expects hyphens.
# Normalising here keeps the conversion in exactly one place.
func _export_name(layout: String) -> String:
	return layout.replace("_", "-")
