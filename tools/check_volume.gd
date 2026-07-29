extends SceneTree

# Verifies that the exported surface encloses exactly the voxel solid it was
# built from.
#
#   godot --headless --script res://tools/check_volume.gd
#
# Hidden-face culling is the one change in the v2 work that can silently ruin a
# model: cull one face too many and the shape gets a hole that no triangle
# count, bounds check or viewport glance will catch.
#
# Counting shared edges does NOT catch it — greedy meshing merges faces into
# rectangles of unequal size, so a large quad meeting two small ones leaves a
# T-junction, and every such junction looks like an open edge while the surface
# is in fact geometrically closed.
#
# Signed volume does catch it. By the divergence theorem a closed surface
# integrates to the volume it bounds, T-junctions and all. Two coincident
# interior faces contribute equal and opposite amounts and cancel, so culling
# them cannot move the number — while dropping a face that was genuinely on the
# surface opens the integral and moves it a lot. The voxel grid gives the answer
# independently: a solid cell is one cube, a prism is exactly half of one.

const GX := 32
const GY := 32
const GZ := 32
const CELL := 1.0 / 32.0

const LAYOUTS := ["cube", "octagon_full", "octagon_half",
	"ramp", "gable", "diagwall", "diamond", "chamfered", "cross", "panel",
	"slab_quarter", "slab_half", "stairs_4", "pipe_quarter"]


func _initialize() -> void:
	print("shape            cell volume    mesh volume        error")
	print("----------------------------------------------------------")
	var bad := 0
	for layout in LAYOUTS:
		if not _check(layout):
			bad += 1
	print("")
	if bad == 0:
		print("PASS  every shape's surface encloses exactly its voxel solid")
	else:
		print("FAIL  %d shape(s) do not — the surface is open or has stray faces" % bad)
	quit(1 if bad > 0 else 0)


func _check(layout: String) -> bool:
	var cells: Array = ShapeBuilder.build(layout, GX, GY, GZ)

	var unit := CELL * CELL * CELL
	var cell_vol := 0.0
	for x in range(GX):
		for y in range(GY):
			for z in range(GZ):
				match cells[x][y][z][0]:
					CellTypes.Type.SOLID: cell_vol += unit
					CellTypes.Type.PRISM: cell_vol += unit * 0.5

	var faces: Array = MeshExporter._collect_faces(cells, GX, GY, GZ, CELL, GX * CELL / 2.0, GZ * CELL / 2.0)
	var mesh_vol := absf(_signed_volume(faces))

	var err := absf(mesh_vol - cell_vol)
	# Vector3 is single-precision; a few thousand triangles of accumulation lands
	# around 1e-7, while one missing face on a 32-cell shape is ~1e-3.
	var ok := err < 1e-5
	print("%-14s %13.8f %14.8f %12.8f  %s" % [layout, cell_vol, mesh_vol, err, "ok" if ok else "<-- LEAK"])
	return ok


func _signed_volume(faces: Array) -> float:
	var vol := 0.0
	for f in faces:
		var n: Vector3 = f[1]
		var verts: Array = f[2]
		var cross: Vector3 = (verts[1] - verts[0]).cross(verts[2] - verts[0])
		var o: Array = verts
		if cross.dot(n) <= 0:
			o = verts.duplicate()
			o.reverse()
		for t in range(1, o.size() - 1):
			var a: Vector3 = o[0]
			var b: Vector3 = o[t]
			var c: Vector3 = o[t + 1]
			vol += a.dot(b.cross(c)) / 6.0
	return vol
