# PrismCraft

A voxel editor built in Godot 4 for authoring **block shapes** and exporting them
as clean, low-poly `.glb` meshes.

PrismCraft is a shape tool, not a texture tool. A model is pure geometry —
solid cells and 45° prism cells on a 32³ grid — and the exported mesh carries
positions and flat normals and nothing else. Texturing is the consumer's job:
it computes UVs in-shader from world position, so anything the file might say
about colour or materials would be discarded.

## Requirements

- Godot 4.3+

## Getting started

Open the project in Godot and run it (F5), or work headlessly:

```
godot --headless --script res://scripts/batch_export.gd -- exports/
```

## The export contract

Every exported shape must satisfy all of the following. The exporter checks the
bytes it is about to write and **refuses to write a file that fails**, naming
the rule that broke — a silently non-compliant export is the failure this
version exists to remove.

- Unit cell: `x, z ∈ [-0.5, 0.5]`, `y ∈ [0, 1]`, origin bottom-centre, Y-up
- One mesh, one primitive, one node, no transform, no skin, no animation
- Indexed triangles, **flat per-face normals**, wound to agree with the normal
- No UVs, no vertex colours, no materials, no embedded images
- At most 500 triangles

Flat normals are load-bearing rather than stylistic: the consumer picks a
texture projection plane from the normal, so a normal shared across a face
boundary would flip the projection mid-face and leave a visible seam.

## Shape library

Fourteen shapes, chosen from **File → Shape Library** (Ctrl+L). Shapes with more
than one sensible placement offer an orientation alongside.

`cube`, `ramp`, `gable`, `diagwall`, `diamond`, `chamfered`, `cross`, `panel`,
`slab_quarter`, `slab_half`, `stairs_4`, `pipe_quarter`, `octagon_full`,
`octagon_half`

Every one is 90°/45° geometry, which a voxel grid plus prism cells expresses
exactly — the octagon is a true regular octagon (its chamfer is sized so all
eight sides come out equal) and `pipe_quarter` is a quarter of an octagonal
ring. Nothing in the library is a stairstepped approximation of a curve.

Current triangle counts, all inside the 500 budget:

| shape | tris | shape | tris |
|---|---|---|---|
| cube | 12 | diamond | 252 |
| panel | 12 | diagwall | 240 |
| slab-quarter | 12 | ramp | 194 |
| slab-half | 12 | pipe-quarter | 176 |
| cross | 36 | octagon-full | 164 |
| stairs-4 | 36 | gable | 130 |
| chamfered | 84 | octagon-half | 100 |

## Tools

| Tool | Description |
|------|-------------|
| Pencil | Place a single voxel |
| Box Fill | Fill a rectangular region (two clicks) |
| Eraser | Remove a single voxel |
| Box Erase | Clear a rectangular region (two clicks) |
| Extrude | Click and drag on a surface to push or pull it |
| Line | Draw a line on the current floor layer |
| Rectangle | Draw a rectangle outline on the current floor layer |
| Oval | Draw an ellipse outline on the current floor layer |
| Smooth | Click-drag along a sharp edge to select it, then choose chamfer depth |
| Shift | Move the whole model along an axis |

Hold **Shift** with Line to lock to an axis, with Rectangle to force a square, or
with Oval to force a circle. **Right-click** the Rect or Oval tool button to
toggle **Center-out** mode ("(C)" on the button): the first click sets the
centre and dragging defines the extent outward.

## Controls

| Input | Action |
|-------|--------|
| Left Click | Use current tool |
| Right Click Drag | Orbit camera |
| Middle Click Drag | Pan camera |
| Scroll Wheel | Zoom in/out |
| Up / Down | Change floor layer |
| Shift+Up / Shift+Down | Change ceiling layer (-1 = off) |
| Tab | Toggle Solid / Prism cell type |
| Q / E | Rotate prism orientation |
| Ctrl+N / Ctrl+O / Ctrl+S | New / Open / Save |
| Ctrl+Shift+S | Save As |
| Ctrl+L | Shape Library |
| Ctrl+Z | Undo |
| Escape | Cancel current operation |

## File format

Working models are saved as Godot resources (`VoxelDefinition`): grid
dimensions, cell data, and `block_shape` — the id of the library shape the model
came from, if any. Save as compressed `.res` or text `.tres`.

**File → Export Model (.glb)** writes the mesh. Export naming uses the shape id,
lowercase and hyphen-separated (`slab-quarter`, `stairs-4`); the builders use
underscores internally and the conversion happens at export.

## How the mesh gets small

Three passes, in order, take a solid cube from 12,288 triangles to 12:

1. **Greedy meshing** merges adjacent coplanar faces per axis-aligned slice.
   With no per-voxel colour to split them, a cube collapses to 6 quads.
2. **Hidden-face culling** drops prism faces buried against solid material. A
   prism covers exactly two of its cell's six faces — its legs — so only a leg
   can hide a neighbour or be hidden. Roughly half of every prism shape's
   triangles were interior surfaces before this.
3. **Coplanar merge** fuses faces the greedy pass cannot reach, because it works
   one axis-aligned slice at a time and a prism's hypotenuse is never in one. A
   32-cell ramp slope becomes a single quad.

## Verification

The tool cannot be eyeballed for correctness — a hole, a sliver or a
zero-area triangle all look fine in a viewport — so the checks are explicit and
runnable:

```
godot --headless --script res://tools/test_merge.gd            # coplanar merge unit tests
godot --headless --script res://tools/check_volume.gd          # surfaces enclose their voxel solid
godot --headless --script res://tools/shape_fingerprint.gd     # shape geometry hashes
godot --headless --script res://tools/export_shapes.gd -- out/ # build + export the library
godot --headless --script res://tools/validate_shapes.gd -- out/
```

`check_volume` is the one that catches a bad cull. Counting shared edges cannot:
greedy meshing leaves T-junctions that read as open edges on a closed surface.
Signed volume is immune to that — by the divergence theorem a closed surface
integrates to the volume it bounds, two coincident interior faces cancel, and a
genuinely missing face does not. The voxel grid supplies the expected answer
independently.

`shape_fingerprint` hashes cell type and orientation with colour excluded. It
exists because passing validation is not evidence that geometry survived a
refactor: a builder that quietly places different cells produces a
different-but-consistent model, and every other check would agree with it.

## Architecture

- `scripts/editor_main.gd` — editor logic, UI, input, tools
- `scripts/cell_types.gd` — cell type enum, prism orientation and occlusion helpers
- `scripts/shape_builder.gd` — every library shape, built as geometry, with
  rotate-Y / rotate-X / vertical-flip orientation transforms
- `scripts/mesh_exporter.gd` — greedy meshing, prism emission and culling, GLB writing
- `scripts/coplanar_merge.gd` — merges coplanar quads into maximal rectangles
- `scripts/glb_validator.gd` — the export contract, shared by the exporter and the CLI
- `scripts/block_mesh_builder.gd` — viewport meshes from cell arrays
- `scripts/voxel_definition.gd` — save/load resource
- `scripts/batch_export.gd` — headless build + export of the whole library
- `scripts/orbit_camera.gd`, `scripts/view_cube.gd` — camera and orientation widget
