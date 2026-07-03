extends SceneTree
# Headless batch: build + GLB-export every legal texture in a folder in one pass.
#
#   godot --headless --script res://scripts/batch_export.gd -- <in_dir> [out_dir]
#
# <in_dir>   folder of textures named per the naming convention (default res://textures)
# [out_dir]  where the .glb files go (default <in_dir>/exports)
#
# Reuses the exact internal build + export code paths (BlockImporter / MeshExporter),
# so batch and manual import can never drift. Block mode geometry (32x32x32).
# Re-running overwrites same-ID files rather than duplicating.

const GX := 32
const GY := 32
const GZ := 32
const CELL := 1.0 / 32.0

# Shape tokens that can appear as the <shape> field in a filename, longest first
# so multi-word tokens peel before their prefixes (octagon_half before octagon).
const SHAPE_TOKENS := [
	"octagon_half", "slab_quarter", "slab_half", "pipe_quarter", "stairs_2", "stairs_4",
	"octagon", "capped", "net", "diamond", "chamfered", "cross", "ramp", "gable",
	"diagwall", "opening", "panel",
]

func _initialize() -> void:
	var uargs := OS.get_cmdline_user_args()
	var in_dir := uargs[0] if uargs.size() >= 1 else "res://textures"
	var out_dir := uargs[1] if uargs.size() >= 2 else in_dir.path_join("exports")
	_run(in_dir, out_dir)
	quit()

func _run(in_dir: String, out_dir: String) -> void:
	var d := DirAccess.open(in_dir)
	if d == null:
		printerr("[batch] cannot open input folder: ", in_dir)
		return
	DirAccess.make_dir_recursive_absolute(out_dir)

	var pngs: Array = []
	for f in d.get_files():
		if f.to_lower().ends_with(".png"):
			pngs.append(f)
	pngs.sort()

	var built := 0
	var exported := 0
	var skipped: Array = []      # [filename, reason]
	var failed: Array = []       # [id, reason]
	var by_role := {}            # role -> count

	for f in pngs:
		var path := in_dir.path_join(f)
		var img := Image.new()
		if img.load(path) != OK:
			skipped.append([f, "image load failed"])
			continue
		var w := img.get_width()
		var h := img.get_height()
		var layout := CellTypes.validate_block_texture(w, h, GX, GY)
		if layout == "":
			skipped.append([f, "unsupported size %dx%d" % [w, h]])
			continue

		var cells := BlockImporter.build_cells(layout, img, GX, GY, GZ, BlockImporter.default_opt(layout))
		built += 1

		var block_id := _block_id(f)
		var out_path := out_dir.path_join(block_id + ".glb")
		var tris := MeshExporter.export_glb(out_path, cells, GX, GY, GZ, CELL)
		var role := block_id.split(".")[0]
		if tris > 0:
			exported += 1
			by_role[role] = by_role.get(role, 0) + 1
			print("[ok]  %-40s -> %s.glb  (%d tris)" % [f, block_id, tris])
		else:
			failed.append([block_id, "export produced no geometry"])
			print("[fail] %-40s -> export empty" % f)

	_summary(in_dir, out_dir, pngs.size(), built, exported, skipped, failed, by_role)

# Filename -> block ID. Strips the extension and the trailing _WxH, peels a known
# shape token (kept verbatim), and joins the remaining fields with dots.
#   wall_brick_32x32.png          -> wall.brick
#   form_wood_stairs_4_80x64.png  -> form.wood.stairs_4
func _block_id(filename: String) -> String:
	var base := filename.get_basename()
	var re := RegEx.new()
	re.compile("_\\d+x\\d+$")
	var m := re.search(base)
	if m:
		base = base.substr(0, m.get_start())
	var shape := ""
	for tok in SHAPE_TOKENS:
		if base.ends_with("_" + tok):
			shape = tok
			base = base.substr(0, base.length() - tok.length() - 1)
			break
	var id := base.replace("_", ".")
	if shape != "":
		id += "." + shape
	return id

func _summary(in_dir: String, out_dir: String, total: int, built: int, exported: int, skipped: Array, failed: Array, by_role: Dictionary) -> void:
	print("\n==================== batch export summary ====================")
	print("input:   ", in_dir)
	print("output:  ", out_dir)
	print("textures found: %d | built: %d | exported: %d | skipped: %d | failed: %d" % [total, built, exported, skipped.size(), failed.size()])
	if not by_role.is_empty():
		print("\nexported by role:")
		var roles := by_role.keys()
		roles.sort()
		for r in roles:
			print("  %-12s %d" % [r, by_role[r]])
	if not skipped.is_empty():
		print("\nskipped:")
		for s in skipped:
			print("  %-40s %s" % [s[0], s[1]])
	if not failed.is_empty():
		print("\nfailed:")
		for fe in failed:
			print("  %-40s %s" % [fe[0], fe[1]])
	print("=============================================================")
