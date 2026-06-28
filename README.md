# PrismCraft

A 3D voxel editor built in Godot 4 for designing block definitions and character models. Supports solid cubes and right-isosceles prism cells with a 16-color palette.

## Requirements

- Godot 4.3+

## Getting Started

Open the project in Godot and run it (F5).

## Editor Modes

- **Block** (32x32x32) -- for designing individual block definitions
- **Character** (64x128x64) -- for designing character models at higher resolution

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
| Tab | Toggle Solid / Prism cell type |
| Q / E | Rotate prism orientation |
| 1-8 | Quick-select palette color |
| Escape | Cancel current operation |
| Ctrl+N | New |
| Ctrl+O | Open |
| Ctrl+S | Save |
| Ctrl+Z | Undo |
| Ctrl+I | Import PNG |

## Features

- **16-color palette** with named colors
- **Prism cells** with 12 orientations (3 axes x 4 corners) for diagonal geometry
- **3D view cube** in the top-right corner for quick camera orientation -- click a face to snap to that view, or drag to orbit
- **Import PNG** to place a flat image as voxels mapped to the nearest palette colors
- **Import Block Texture** to wrap a PNG onto all 6 faces of a solid block
- **Import Character Sprites** to generate a rough 3D model from a front and side PNG using silhouette intersection
- **Export OBJ** generates an optimized mesh using greedy face merging, with materials per palette color
- **Unsaved changes protection** on New, Open, mode switch, and quit
- **Extrude tool** with flood-fill surface detection for pushing/pulling connected faces
- **Axis Overlay** toggle (View menu) shows semi-transparent planes at the grid center along X and Z axes
- **Mirror mode** (View menu: Mirror X / Mirror Z) mirrors all drawing operations across the center plane, with a cyan cursor showing the mirrored position
- **Center-out drawing** for Rect and Oval tools (right-click the tool button to toggle)
- **Character presets** (male/female) generated on startup in `res://definitions/`

## File Format

Definitions are saved as Godot `.tres` resources using the `VoxelDefinition` class, which stores grid dimensions, edit mode, and run-length encoded cell data.

## Architecture

- `scripts/editor_main.gd` -- main editor logic, UI, input handling, and tools
- `scripts/cell_types.gd` -- cell type enum, palette colors, and orientation names
- `scripts/block_mesh_builder.gd` -- generates meshes from cell arrays with face culling
- `scripts/mesh_exporter.gd` -- exports optimized OBJ with greedy meshing and MTL palette materials
- `scripts/voxel_definition.gd` -- resource class for saving/loading definitions
- `scripts/orbit_camera.gd` -- orbit camera with right-click drag, pan, and zoom
- `scripts/view_cube.gd` -- 3D orientation widget with face clicking and drag rotation
