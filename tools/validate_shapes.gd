extends SceneTree

# Checks exported .glb shapes against the v2 export contract.
#
#   godot --headless --script res://tools/validate_shapes.gd -- <file-or-dir> [...]
#
# Exits non-zero if any file fails, so it can gate a build. The rules live in
# GlbValidator so this and the exporter's inline check can never disagree.

func _initialize() -> void:
	var targets := OS.get_cmdline_user_args()
	if targets.is_empty():
		print("usage: godot --headless --script res://tools/validate_shapes.gd -- <file-or-dir> [...]")
		quit(2)
		return

	var files: Array = []
	for t in targets:
		if t.to_lower().ends_with(".glb"):
			files.append(t)
		else:
			var d := DirAccess.open(t)
			if d == null:
				printerr("cannot open: ", t)
				quit(2)
				return
			for f in d.get_files():
				if f.to_lower().ends_with(".glb"):
					files.append(t.path_join(f))
	files.sort()

	if files.is_empty():
		print("no .glb files found")
		quit(2)
		return

	var failed := 0
	for path in files:
		var res := GlbValidator.validate_file(path)
		var stats: Dictionary = res["stats"]
		var tris: int = stats.get("triangles", 0)
		if res["ok"]:
			print("PASS  %-18s %4d tris" % [path.get_file(), tris])
		else:
			failed += 1
			print("FAIL  %-18s %4d tris" % [path.get_file(), tris])
			for e in res["errors"]:
				print("        - %s" % e)

	print("")
	print("%d file(s), %d passed, %d failed" % [files.size(), files.size() - failed, failed])
	quit(1 if failed > 0 else 0)
