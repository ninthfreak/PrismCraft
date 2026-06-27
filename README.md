# PrismCraft

A Minecraft-style voxel game built in Godot 4, where blocks are **right-isosceles prisms** instead of cubes. Each square cell is split diagonally into two triangular prisms (A and B), with the triangular faces pointing up and down.

## Requirements

- Godot 4.3+

## How to Play

Open the project in Godot and run it (F5).

### Controls

| Key | Action |
|-----|--------|
| WASD | Move |
| Mouse | Look around |
| Space | Jump |
| Left Click | Break prism |
| Right Click | Place prism |
| 1-6 | Select block type |
| Escape | Release mouse cursor |

### Block Types

1. Grass
2. Dirt
3. Stone
4. Sand
5. Wood
6. Leaves

## Architecture

- **Prism geometry**: Each world cell contains two right-isosceles prism slots (A and B). Two filled slots form a full square block; breaking individual prisms creates diagonal surfaces.
- **Chunk system**: The world is divided into 16x16 chunks, loaded/unloaded based on player distance.
- **Face culling**: Only exposed prism faces are rendered, using neighbor lookups across chunk boundaries.
- **Procedural terrain**: Simplex noise heightmap with grass, dirt, stone, and sand layers, plus simple tree generation.
