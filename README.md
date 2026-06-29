# PrismCraft

A 3D voxel editor built in Godot 4 for designing block definitions and character models. Supports solid cubes and right-isosceles prism cells with RGB565 high color (65,536 colors).

## Requirements

- Godot 4.3+

## Getting Started

Open the project in Godot and run it (F5).

## Editor Modes

- **Block** (48x48x48) -- for designing individual block definitions. Each voxel is 1/48 of a unit, so one block = 1x1x1 unit in-game.
- **Character** (96x192x96) -- for designing character models at double resolution. The grid is 2x4x2 blocks worth of space but at 1/96 unit per voxel, so a character stands exactly **2 blocks tall** (2 units) despite the finer detail.

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
| 1-8 | Quick-select favorite color |
| Escape | Cancel current operation |
| Ctrl+N | New |
| Ctrl+O | Open |
| Ctrl+S | Save |
| Ctrl+Z | Undo |
| Ctrl+I | Import PNG |

## Features

- **RGB565 color** with full color picker and 16 favorite color shortcuts
- **Prism cells** with 12 orientations (3 axes x 4 corners) for diagonal geometry
- **3D view cube** in the top-right corner for quick camera orientation -- click a face to snap to that view, or drag to orbit
- **Import PNG** to place a flat image as voxels with direct RGB565 color encoding
- **Import Block Texture** to wrap a PNG onto all 6 faces of a solid block
- **Import Character Sprites** to generate a rough 3D model from a front and side PNG using silhouette intersection
- **Export OBJ** generates an optimized mesh using greedy face merging, with materials per unique color
- **Unsaved changes protection** on New, Open, mode switch, and quit
- **Extrude tool** with flood-fill surface detection for pushing/pulling connected faces
- **Axis Overlay** toggle (View menu) shows semi-transparent planes at the grid center along X and Z axes
- **Mirror mode** (View menu: Mirror X / Mirror Z) mirrors all drawing operations across the center plane, with a cyan cursor showing the mirrored position
- **Center-out drawing** for Rect and Oval tools (right-click the tool button to toggle)
- **Character presets** (male/female) generated on startup in `res://definitions/`

## Model Dimensions

| Mode | Grid | Voxel Size | World Size | Notes |
|------|------|-----------|------------|-------|
| Block | 48x48x48 | 1/48 unit | 1x1x1 | Standard building block |
| Character | 96x192x96 | 1/96 unit | 1x2x1 | Same height as 2 stacked blocks |

Characters have double the voxel resolution of blocks in every axis, giving 4x the surface detail while occupying the same physical footprint as a 1x2x1 column of blocks. Grid dimensions are chosen to be divisible by 2, 3, 4, 6, 8, 12, 16, and 24.

## File Format

Working definitions are saved as Godot `.tres` resources using the `VoxelDefinition` class, which stores grid dimensions, edit mode, and run-length encoded cell data. Use **Export OBJ** (File menu) to generate an optimized mesh for game use -- greedy meshing merges coplanar same-color faces into larger quads, dramatically reducing triangle count.

## Architecture

- `scripts/editor_main.gd` -- main editor logic, UI, input handling, and tools
- `scripts/cell_types.gd` -- cell type enum, RGB565 color encoding, favorite colors, and orientation names
- `scripts/block_mesh_builder.gd` -- generates meshes from cell arrays with face culling
- `scripts/mesh_exporter.gd` -- exports optimized OBJ with greedy meshing and MTL materials per color
- `scripts/voxel_definition.gd` -- resource class for saving/loading definitions
- `scripts/orbit_camera.gd` -- orbit camera with right-click drag, pan, and zoom
- `scripts/view_cube.gd` -- 3D orientation widget with face clicking and drag rotation
