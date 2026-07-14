# PrismCraft — Block Format Manifest

Complete reference for the voxel **cell encoding** and every **block-texture atlas** the editor imports. This is the human-readable companion to [`block_formats.json`](block_formats.json) (machine-readable). The source of truth in code is `scripts/cell_types.gd` (validation + color encoders) and `scripts/shape_builder.gd` (shape geometry).

---

## 1. Grid

| Mode | Grid (X×Y×Z) | Voxel size | World size |
|------|--------------|-----------|------------|
| Block | 32 × 32 × 32 | 1/32 unit | 1 × 1 × 1 |
| Character | 64 × 128 × 64 | 1/64 unit | 1 × 2 × 1 |

Block textures target **block mode**. The cube and octagon formats are grid-relative (they scale with `grid_x`); the predefined shapes are fixed 32-based sizes and import in block mode only.

---

## 2. Cell encoding

Each voxel cell is an 8-element array:

```
[ type, orientation, c_top, c_bottom, c_right, c_left, c_front, c_back ]
    0        1          2       3         4        5        6        7
```

- **type** — `EMPTY (0)`, `SOLID (1)`, `PRISM (2)`.
- **orientation** — for prisms only: `axis*4 + corner`.
  - axis: `0 = Y`, `1 = X`, `2 = Z` (the extrusion axis).
  - corner: `0 = SW`, `1 = SE`, `2 = NE`, `3 = NW` (position of the prism's solid right-angle in the cross-section plane).
- **c_top … c_back** — per-face color ints, one per face:

  | slot | index | axis |
  |------|-------|------|
  | c_top | 2 | +Y |
  | c_bottom | 3 | −Y |
  | c_right | 4 | +X |
  | c_left | 5 | −X |
  | c_front | 6 | +Z |
  | c_back | 7 | −Z |

> **Prisms carry a color per face.** A prism has 5 faces — 2 caps, 2 axis-aligned legs, and 1 diagonal hypotenuse — and each maps to a **distinct** cell slot (`slot_for_normal`, using the same Y→X→Z precedence as `face_index_from_normal`; the hypotenuse resolves to a free slot, collision-free across all 12 orientations). So a prism can have a different color on each side, editable with the Paint/Eyedropper tools. The shape importers use this too: edge prisms carry cap/ribbon/end-ring colors on their top and bottom triangles and strip/wall colors on their lateral faces. Uniform prisms (all slots equal) render as one color. The orientation transforms (rotate-Y / rotate-X / vertical flip) remap prism face slots normal-exactly — the hypotenuse slot moves by `prism_hyp_slot`, not by the axis-face tables, since diagonal normals collapse under the Y→X→Z slot precedence.

---

## 3. Color packing

| Format | Used for | Bit layout | Colors |
|--------|----------|-----------|--------|
| **RGB565** | opaque cells | `RRRRR GGGGGG BBBBB` | 65 536 |
| **RGB5551** | cutout cells (1-bit alpha) | `RRRRR GGGGG BBBBB A` | 32 768 |

- **Routing:** if **any** source pixel has alpha `< 255`, the whole texture is treated as transparent and every cell packs to **RGB5551** (`alpha_bit = source_alpha >= 128 ? 1 : 0`). Otherwise all cells pack to **RGB565**. Fully-opaque RGBA exports stay on 565.
- **Flag bit:** stored RGB5551 ints carry `0x10000` so the decoder can tell the two formats apart.
- **Threshold:** import cutoff `128` corresponds to shader cutoff `0.5` (`ALPHA_THRESHOLD`).
- **Render:** cutout faces alpha-test (`discard` when alpha `< 0.5`), draw double-sided, and **never occlude neighboring faces** — holes show the geometry behind, and adjacent cutout faces both render (canopy layering).

---

## 4. Import rule (strict 1:1)

One texel → exactly one voxel face, **nearest-neighbor, never scaled, filtered, padded, cropped, or interpreted.** A texture whose `(width, height)` does not **exactly** match a registry entry below is **rejected with a warning naming the nearest legal sizes; nothing is imported.** There is no resampling path.

---

## 5. Format registry

Dimensions are the atlas `width × height` in pixels. Block mode, `F = 32`.

### Cube formats (grid-relative)

| Format | Size | Atlas layout |
|--------|------|--------------|
| **uniform** | 32×32 | one cell on all 6 faces |
| **capped** | 64×32 | left 32 = 4 sides · right 32 = shared top+bottom cap |
| **net** | 96×64 | 3×2 grid — row 1 top\|front\|right, row 2 bottom\|back\|left |

### Octagon formats (grid-relative)

| Format | Size | Geometry | Atlas layout |
|--------|------|----------|--------------|
| **octagon** (full) | 124×32 | footprint 32, chamfer 9 (axis 14 / diag 9), corners are prisms | strip `14,9,14,9,14,9,14,9` CCW from +X, then 32×32 cap |
| **octagon_half** | 60×32 | footprint 16 centered (8-voxel empty margins), chamfer 5 (axis 6 / diag 5) | strip `6,5,6,5,6,5,6,5`, then 16×16 cap |

### Predefined shapes (block mode only, fixed sizes)

| Format | Size | Geometry | Orientation options |
|--------|------|----------|---------------------|
| **diamond** | 96×32 | diamond column, chamfer 16 (4 diagonal faces, no axis faces) | — (4-fold symmetric) |
| **chamfered** | 144×32 | cube with 4 vertical edges chamfered (c=4, axis 24 / chamfer 4) | — |
| **cross** | 160×32 | plus column, central 16×16 + four 16-wide × 8-deep arms (pure cubes) | — |
| **ramp** | 128×64 | 45° wedge, one prism per step | slope up +X/+Z/−X/−Z, each also inverted (8) |
| **gable** | 128×48 | two 45° slopes at a centered ridge, half-height (ridge y=16) | ridge along Z or X (2) |
| **diagwall** | 112×32 | diagonal wall band, thickness 8, prisms on both long faces | diagonal NE-SW or NW-SE (2) |
| **panel** | 64×34 | flat cube 32×32×1 | on floor/ceiling/±X wall/±Z wall (6) |
| **slab_quarter** | 64×48 | flat cube 32×32×8 | on floor/ceiling/±X wall/±Z wall (6) |
| **slab_half** | 64×64 | flat cube 32×32×16 | on floor/ceiling/±X wall/±Z wall (6) |
| **stairs_4** | 80×64 | solid staircase, 4 steps of 8 | climb +X/+Z/−X/−Z (4) |
| **pipe_quarter** | 120×32 | quadrant of a 64×64 hollow octagon ring; four rotations close a ring | quadrant 0/90/180/270° (4) |

Orientation is chosen in the import preview — **one atlas serves every rotation** (no separate textures). Rotations are applied to the built cell grid via rotate-Y / rotate-X / vertical-flip transforms that remap position, prism orientation, and per-face colors together.

#### Shape atlas details

- **diamond** — cols 0–63: 4 diagonal faces ×16 (CCW from the +X-facing NE face); cols 64–95: 32×32 cap.
- **chamfered** — cols 0–111: strip `24,4,24,4,24,4,24,4`; cols 112–143: cap.
- **cross** — cols 0–127: strip `16,8,8,16,8,8,16,8,8,16,8,8`; cols 128–159: cap.
- **ramp** — row 1 (y0–31): `slope | back | bottom | unused`; row 2 (y32–63): `side-L | side-R | unused`.
- **gable** — row 1 (y0–15): `slope-A | slope-B | end-A | end-B` (each 32×16); row 2 (y16–47): `bottom` (32×32).
- **diagwall** — `wall-A(32) | wall-B(32) | end-A(8) | end-B(8) | top-plan(32×32)`. The top plan is a literal **top-down view**: texel `(x,z)` is the top of cell `(x,z)`, so the diagonal band appears diagonally in the atlas exactly as seen from above — no shear, trivially 1:1 (one texel per top face). The **bottom** shares the same texel (top-wins, like the shape caps; a wall's underside is rarely seen). Ends (end-A = SW, end-B = NE) are **2:1**: the band is `2t−1 = 15` diagonals wide but an end cell is only `t = 8`, so the two ends of a side share their 8-wide region. Boundary-prism caps take the plan; their hypotenuses keep the wall sample.
- **panel / slab_quarter / slab_half** — row 1: `top | bottom` (32×32 each); following rows: `N|S` then `E|W`, each 32 × thickness (1 / 8 / 16).
- **stairs_4** — row 1: `tread(8) | riser(8) | back(32) | bottom(32)`; row 2: `side(32) | unused(48)`.
- **stairs tread/riser conventions** — the tread cell is a **plan view** of one step strip: u = x within the step (0 = riser edge), v = `F−1−z` (north-up, like slab tops). The riser cell is the riser elevation **rotated 90°**: u = height within the step (0 = bottom), v = z. The shared strips are sampled **shifted by `ss` along z on alternating steps** (`so = (step%2)·ss`), so the brick coursing climbs the stair as a staggered running bond rather than lining up in vertical columns.
- **pipe_quarter** — `outer-arc(45) | inner-arc(41) | end-ring(32) | cut(2)`. The arcs map 1:1 along the unrolled quadrant perimeters (outer: 13 flat + 19 diagonal + 13 flat = 45 columns; bore: 11+19+11 = 41; v = height). Diagonal runs paint the wall prisms' hypotenuse faces; both walks run in one rotational direction so four rotations tile the texture continuously around the ring.

---

## 6. Texturing fidelity — strict 1:1

**Every exposed face maps to exactly one atlas texel** — cube, octagon, and all
predefined shapes, including prism caps, legs and hypotenuses, the pipe's arcs
and its radial cut faces, and the diagonal wall's top/bottom. No sampling,
averaging, resampling, or guessing on any visible face.

The one deliberate exception is **symmetric faces that share a texel by design**:
a shape's top and bottom caps share the cap region, and a diagonal wall's two
end faces share their 8-wide end region. Reconstruction keeps the most-visible
of a shared pair (top > sides > bottom), and the Texture Editor **warns** when
per-face edits diverge from what the atlas can hold, so it is never silent.

Two more clarifications, neither a violation:

- **Interior / hidden faces** (between two solids) carry a dominant-color fill, but they are never visible and have no atlas texel — there is nothing for them to be 1:1 with.
- **A prism face is one voxel color by definition.** A slope takes one color per cell (one atlas texel per cell), which *is* 1:1 — not a gradient across the diagonal face. Edge prisms carry a distinct color per face (caps from the cap/ribbon/end-ring cells, laterals from the strip/wall cells), individually editable with Paint/Eyedropper.

Because import is strictly 1:1, it is exactly invertible: the Texture Editor rebuilds a block's atlas from its voxels by running the importer on a probe atlas to recover the texel↔face map, so the editor can never desync from what's on the block.

---

## 7. Naming (convention v3.6)

Texture files and block IDs follow:

```
<material-variant>_<shape>_<WxH>.png     (files)
<material-variant>.<shape>               (block IDs)
```

**No roles** (removed in v3 — use is the builder's decision, inferred from shape + material). **Shape is mandatory** on every texture — the 32×32 uniform block carries the explicit `cube` token (`brick_cube_32x32.png`), nothing is implicit. The `shape` token matches a registry format above (`cube`, `capped`, `net`, `octagon`, `octagon-half`, `diamond`, `chamfered`, `cross`, `ramp`, `gable`, `diagwall`, `pipe-quarter`, `panel`, `slab-quarter`, `slab-half`, `stairs-4`).

**Fields use hyphens internally** (`stone-block`, `steel-corrugated`, `stone-flecked-coal`, `octagon-half`), so the **only underscores are the field separators**. The block ID is the filename minus `_WxH` with those underscores turned into dots — no vocabulary list needed to parse it. Variants describe intrinsic material differences only (`corrugated`, `plank`, `rusted`, `painted-<color>`, `flecked-<mineral>`…); transient/environmental states (`damp`, `wet`, `snowy`, `frozen`) are shader effects, never baked into textures.

---

## 8. GLB export (textured, spec v1)

Runtime consumers instance tens of thousands of blocks, so exports must be
**low-poly with the detail in a texture, never in geometry**. `MeshExporter.export_glb_textured`
(used by the batch pipeline and the editor's *Export Model → .glb*) emits:

- **Shape-minimal geometry.** Coplanar exposed faces merge regardless of color,
  so a textured cube is **12 triangles** (not ~9k texel-quads), a ramp/gable ≤ 24,
  etc. Prisms keep their real diagonal faces.
- **An embedded 6-sided atlas.** A single PNG in the GLB binary chunk, laid out as
  a **cube net** — 3 columns (top/bottom · front/back · right/left) × 2 rows.
  For a 32³ block that is the familiar **96×64 "net"** sheet, and it re-imports as
  a `net` cube atlas (same per-face read conventions as `build_cube`).
- **UV0 per vertex**, texel edges on grid lines, `NEAREST` sampler, `CLAMP_TO_EDGE`.
- **One material `voxel`** (metallic 0, roughness 1, `baseColorTexture`), `OPAQUE`
  except cutout blocks which use `alphaMode MASK`, cutoff 0.5. `COLOR_0` is dropped.

**The atlas is an orthographic projection of the exposed surface onto the six
cardinal planes.** Each voxel face = one texel (per-voxel color *is* 1:1, §6), so
the projection is lossless for convex/heightfield shapes (cube, ramp, gable,
stairs, slab, panel). A prism's diagonal face resolves to the cardinal region its
normal most faces (`slot_for_normal`) and projects to its cell's texel.

The **one lossy case is genuine concavity** — two exposed faces with the same
cardinal normal that project onto the same texel (an overhang, a tunnel ceiling
above the block floor in `opening`, the two ends of a `diagwall`). These resolve
**nearest-to-viewer (top-wins)**, exactly the shared-texel rule of §6.
`MeshExporter._last_export_divergence` counts any faces the atlas can't reproduce;
the batch summary and the editor status line report the count so it is never
silent. A block with 0 divergence is a faithful round-trip.

> This is the first place the **6-sided atlas** standard is used. Import/edit still
> use the per-shape sheets of §5; migrating those to 6-sided is a separate step.
