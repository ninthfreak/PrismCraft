extends SceneTree

# Builds every shape in the library and reports its triangle count under three
# pipelines, so the v2 plan can be measured instead of assumed:
#
#   base    today's pipeline — a varied atlas, one colour per voxel
#   uniform every cell the same colour (what stripping colour will produce)
#   merged  uniform, plus the coplanar merge pass
#
#   godot --headless --script res://tools/export_shapes.gd -- <out_dir> [mode]
#
# mode: "base" (default) | "uniform" | "merged" — which variant gets written to
# disk as .glb. All three counts are reported regardless.

const GX := 32
const GY := 32
const GZ := 32
const CELL := 1.0 / 32.0
const BUDGET := 500

const LAYOUTS := [
	"uniform", "capped", "net",
	"octagon_full", "octagon_half",
	"ramp", "gable", "diagwall", "diamond", "chamfered",
	"cross", "panel", "slab_quarter", "slab_half",
	"stairs_4", "pipe_quarter",
]


func _initialize() -> void:
	var uargs := OS.get_cmdline_user_args()
	var out_dir: String = uargs[0] if uargs.size() >= 1 else "user://exports"
	var mode: String = uargs[1] if uargs.size() >= 2 else "base"
	DirAccess.make_dir_recursive_absolute(out_dir)

	print("shape            base  uniform   merged   budget  file")
	print("---------------------------------------------------------------")

	var rows: Array = []
	for layout in LAYOUTS:
		var row := _measure(layout, out_dir, mode)
		if row.is_empty():
			continue
		rows.append(row)
		print("%-14s %6s %8s %8s %8s  %s" % [
			row["shape"], _n(row["base"]), _n(row["uniform"]), _n(row["merged"]),
			("ok" if row["merged"] <= BUDGET and row["merged"] > 0 else "OVER"),
			row["note"]])

	print("")
	_summarise(rows)
	quit(0)


func _measure(layout: String, out_dir: String, mode: String) -> Dictionary:
	var dims := BlockImporter.atlas_dims(layout, GX, GY)
	if dims == Vector2i.ZERO:
		printerr("no atlas dims for layout: ", layout)
		return {}

	var opt: Dictionary = BlockImporter.default_opt(layout)
	var base_cells: Array = BlockImporter.build_cells(layout, _varied_atlas(dims), GX, GY, GZ, opt)
	var uni_cells: Array = BlockImporter.build_cells(layout, _uniform_atlas(dims), GX, GY, GZ, opt)

	var ox := GX * CELL / 2.0
	var oz := GZ * CELL / 2.0
	var base_faces: Array = MeshExporter._collect_faces(base_cells, GX, GY, GZ, CELL, ox, oz)
	var uni_faces: Array = MeshExporter._collect_faces(uni_cells, GX, GY, GZ, CELL, ox, oz)
	var merged_faces: Array = CoplanarMerge.merge(uni_faces)

	var cells_to_write: Array = base_cells
	if mode == "uniform" or mode == "merged":
		cells_to_write = uni_cells

	var name := _export_name(layout)
	var path: String = out_dir.path_join(name + ".glb")
	var written: int = MeshExporter.export_glb(path, cells_to_write, GX, GY, GZ, CELL)

	return {
		"shape": name,
		"base": _tris(base_faces),
		"uniform": _tris(uni_faces),
		"merged": _tris(merged_faces),
		"note": "%s (%d tris on disk)" % [name + ".glb", written],
	}


func _summarise(rows: Array) -> void:
	var base_total := 0
	var uni_total := 0
	var merged_total := 0
	var over_base := 0
	var over_uni := 0
	var over_merged := 0
	for r in rows:
		base_total += r["base"]; uni_total += r["uniform"]; merged_total += r["merged"]
		if r["base"] > BUDGET: over_base += 1
		if r["uniform"] > BUDGET: over_uni += 1
		if r["merged"] > BUDGET: over_merged += 1
	print("totals   base %d   uniform %d   merged %d" % [base_total, uni_total, merged_total])
	print("over the %d-triangle budget:  base %d/%d   uniform %d/%d   merged %d/%d" % [
		BUDGET, over_base, rows.size(), over_uni, rows.size(), over_merged, rows.size()])


func _tris(faces: Array) -> int:
	var n := 0
	for f in faces:
		n += (f[2] as Array).size() - 2
	return n


func _n(v: int) -> String:
	return str(v)


# ShapeBuilder/BlockImporter name shapes with underscores; the consumer expects
# hyphens. Normalising here keeps the conversion in exactly one place.
func _export_name(layout: String) -> String:
	match layout:
		"uniform": return "cube"
		"capped": return "cube-capped"
		"net": return "cube-net"
	return layout.replace("_", "-")


# A different colour per texel — what a real texture looks like, and the reason
# nothing merges today.
func _varied_atlas(dims: Vector2i) -> Image:
	var img := Image.create_empty(dims.x, dims.y, false, Image.FORMAT_RGBA8)
	for y in range(dims.y):
		for x in range(dims.x):
			var h := (x * 73856093) ^ (y * 19349663)
			img.set_pixel(x, y, Color(
				float((h >> 16) & 0xFF) / 255.0,
				float((h >> 8) & 0xFF) / 255.0,
				float(h & 0xFF) / 255.0, 1.0))
	return img


func _uniform_atlas(dims: Vector2i) -> Image:
	var img := Image.create_empty(dims.x, dims.y, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.58, 0.58, 0.58, 1.0))
	return img
