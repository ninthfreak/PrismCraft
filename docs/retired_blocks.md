# Retired Blocks

Shapes that were once part of the roster but have since been removed. Kept here
so the history is discoverable — why a shape went away, and what its atlas looked
like — without cluttering the live format registry (`block_formats.json` /
`block_formats.md`).

Removing a shape retires every material variant that used it: any
`<material>_<shape>_<WxH>.png` source texture becomes orphaned, since there is no
longer a shape token to import it into.

---

## opening (224×32)

**Retired:** 2026-07 · **Reason:** unclear use case; awkward to author and texture.

A cube with a single top edge chamfered at 45° (bevel depth 8), intended as an
arch/coping or lintel piece. Four orientations placed the chamfer on the +Z, +X,
−Z, or −X top edge.

**Atlas layout** — seven 32-wide cells:
`front (0–31, ×24) | chamfer bevel (32–63, ×8) | top (64–95, ×24) | back (96–127) | bottom (128–159) | side-L (160–191) | side-R (192–223)`.
The ±X faces were pentagonal (the top-front corner cut away by the bevel); the
bevel was an X-axis prism (ori 4) whose hypotenuse sampled the `chamfer` cell and
whose ±X caps sampled the adjacent side cells.

It never shipped a committed block texture in the repo — its source atlases lived
only in the texture-library bundle — so retiring it removed the shape definition
(builder, size/validation, editor entries, docs) but deleted no tracked assets.
