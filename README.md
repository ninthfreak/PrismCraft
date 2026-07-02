# PrismCraft

A 3D voxel editor built in Godot 4 for designing block definitions and character models. Supports solid cubes and right-isosceles prism cells with RGB565 high color (65,536 colors) plus RGB5551 1-bit-alpha **cutout** cells for see-through textures (leaves, grates, lantern frames). Includes a library of predefined prism shapes (ramp, octagon, stairs, pipe, and more) imported from exact-size 1:1 texture atlases.

See [`docs/block_formats.md`](docs/block_formats.md) and [`docs/block_formats.json`](docs/block_formats.json) for the full block-format manifest: cell encoding, color packing, and every texture atlas layout.

## Requirements

- Godot 4.3+

## Getting Started

Open the project in Godot and run it (F5).

## Editor Modes

- **Block** (32x32x32) -- for designing individual block definitions. Each voxel is 1/32 of a unit, so one block = 1x1x1 unit in-game.
- **Character** (64x128x64) -- for designing character models at double resolution. The grid is 2x4x2 blocks worth of space but at 1/64 unit per voxel, so a character stands exactly **2 blocks tall** (2 units) despite the finer detail.

## Tools

| Tool | Description |
|------|-------------|
| Pencil | Place a single voxel |
| Paint | Recolor an existing voxel without changing its shape |
| Box Fill | Fill a rectangular region (two clicks) |
| Eraser | Remove a single voxel |
| Box Erase | Clear a rectangular region (two clicks) |
| Extrude | Click and drag on a surface to push or pull it |
| Line | Draw a line on the current floor layer |
| Rectangle | Draw a rectangle outline on the current floor layer |
| Oval | Draw an ellipse outline on the current floor layer |
| Smooth | Click-drag along a sharp edge to select it, then choose chamfer depth |
| Rig Paint | Paint per-voxel bone ownership and overlap regions for the skeleton rig |

Hold **Shift** with Line to lock to an axis, with Rectangle to force a square, or with Oval to force a circle.

**Right-click** the Rect or Oval tool button to toggle **Center-out** mode (indicated by "(C)" on the button). In this mode, the first click sets the center point and dragging defines the extent outward.

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
| Ctrl+Shift+S | Save As |
| 1-8 | Quick-select favorite color |
| Escape | Cancel current operation |
| Ctrl+N | New |
| Ctrl+O | Open |
| Ctrl+S | Save |
| Ctrl+Z | Undo |
| Ctrl+I | Import PNG |

## Features

- **RGB565 color** (opaque) and **RGB5551 cutout** (1-bit alpha) with full color picker and 16 favorite color shortcuts. Any imported pixel with alpha < 255 routes that cell to the cutout path; cutout faces alpha-test in the shader and never occlude neighbors, so holes show what's behind.
- **Prism cells** with 12 orientations (3 axes x 4 corners) for diagonal geometry
- **3D view cube** in the top-right corner for quick camera orientation -- click a face to snap to that view, or drag to orbit
- **Import PNG** to place a flat image as voxels (RGB565, or RGB5551 cutout when the PNG has transparency)
- **Import Block Texture** with strict 1:1 texel-to-voxel mapping, auto-detected by exact dimensions:
  - **32x32** (uniform) -- same texture on all 6 faces
  - **64x32** (capped) -- left half for 4 sides, right half for top and bottom
  - **96x64** (6-face net) -- 3x2 grid: top/front/right on row 1, bottom/back/left on row 2
  - **124x32** (full octagon, F=32) -- variable-width strip (14,9,14,9,14,9,14,9) + 32x32 cap; 1 texel = 1 voxel face
  - **60x32** (half octagon, F=16) -- variable-width strip (6,5,6,5,6,5,6,5) + 16x16 cap; centered post/pillar
  - **Predefined prism shapes** (block mode, exact sizes): **96x32** diamond column, **144x32** chamfered cube column, **160x32** cross/plus column, **128x64** ramp/wedge, **128x48** gable/ridge, **112x32** diagonal wall, **224x32** chamfered opening, **64x34** panel, **64x48** slab_quarter, **64x64** slab_half, **128x32** stairs_2, **80x64** stairs_4, **120x32** pipe_quarter (hollow octagonal pipe -- four rotations close a ring). Each slices its atlas 1:1 onto the shape's faces; orientation (facing / inverted / ridge axis / wall side / quadrant) is chosen in the import preview, so one atlas serves all rotations.
  - Any other size is rejected with a warning listing the legal sizes
- **Import Character Sprites** to generate a rough 3D model from a front and side PNG using silhouette intersection
- **Export Model** (File menu) writes an optimized mesh as glTF binary (`.glb`, recommended) or Wavefront `.obj`, using greedy face merging with materials per unique color
- **Rig Paint tool** and **Rig / Skeleton** window (View menu) for painting per-voxel bone ownership and overlap regions, then bend-testing a rigid segmented skeleton
- **Compare Two Models** (View menu) shows two definitions side by side
- **Unsaved changes protection** on New, Open, mode switch, and quit
- **Extrude tool** with flood-fill surface detection for pushing/pulling connected faces
- **Axis Overlay** toggle (View menu) shows semi-transparent planes at the grid center along X and Z axes
- **Mirror mode** (View menu: Mirror X / Mirror Z) mirrors all drawing operations across the center plane, with a cyan cursor showing the mirrored position
- **Voxel Grid on Model** toggle (View menu) draws per-cell grid lines on the model for readability
- **Center-out drawing** for Rect and Oval tools (right-click the tool button to toggle)
- **Character presets** (male/female) generated on startup in `res://definitions/`

## Model Dimensions

| Mode | Grid | Voxel Size | World Size | Notes |
|------|------|-----------|------------|-------|
| Block | 32x32x32 | 1/32 unit | 1x1x1 | Standard building block |
| Character | 64x128x64 | 1/64 unit | 1x2x1 | Same height as 2 stacked blocks |

Characters have double the voxel resolution of blocks in every axis, giving 4x the surface detail while occupying the same physical footprint as a 1x2x1 column of blocks.

## File Format

Working definitions are saved as Godot resources using the `VoxelDefinition` class, which stores grid dimensions, edit mode, and cell data. Save as compressed `.res` (recommended) or text `.tres`. Use **Export Model** (File menu) to generate an optimized mesh for game use as `.glb` or `.obj` -- greedy meshing merges coplanar same-color faces into larger quads, dramatically reducing triangle count.

The full block-format spec -- cell encoding, color packing, and every texture atlas layout -- lives in [`docs/block_formats.md`](docs/block_formats.md) (human-readable) and [`docs/block_formats.json`](docs/block_formats.json) (machine-readable registry).

## Architecture

- `scripts/editor_main.gd` -- main editor logic, UI, input handling, and tools
- `scripts/cell_types.gd` -- cell type enum, RGB565/RGB5551 color encoding, block-texture size validation, favorite colors, and orientation names
- `scripts/block_mesh_builder.gd` -- generates meshes from cell arrays with face culling (cutout cells never occlude neighbors)
- `scripts/shape_builder.gd` -- builds every predefined shape (ramp, gable, diagonal wall, diamond, chamfered cube, cross, opening, panel/slabs, stairs, pipe-quarter) from exact-size 1:1 atlases, with canonical build + rotate-Y / rotate-X / vertical-flip orientation transforms
- `scripts/mesh_exporter.gd` -- exports optimized `.glb` / `.obj` with greedy meshing and materials per color
- `scripts/voxel_definition.gd` -- resource class for saving/loading definitions
- `scripts/rig_data.gd` -- rigid segmented skeleton: per-voxel bone ownership/overlap, auto-fit, nearest-segment partition
- `scripts/rig_view.gd` -- Rig / Skeleton window: bend-test the painted rig and export a posed scene
- `scripts/compare_view.gd` -- side-by-side comparison of two definitions
- `scripts/orbit_camera.gd` -- orbit camera with right-click drag, pan, and zoom
- `scripts/view_cube.gd` -- 3D orientation widget with face clicking and drag rotation
