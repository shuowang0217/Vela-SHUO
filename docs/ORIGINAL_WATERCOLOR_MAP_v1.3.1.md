# Vela v1.3.1 Watercolor Atlas — narrowly scoped image replacement

**Base:** the previously CI-proven v1.3.1 build, commit
2d0d8814e87c31db4326b40d7bb53053e4450b9c.

**Changes:** Only map artwork and declarations, a separate CI branch,
build number +10 (still version v1.3.1), asset smoke test, and unique
artifact names.

- The light world map is a high-quality WebP encode at the original
  1774 x 887 canvas dimensions of the exact watercolor illustration
  supplied in conversation on 2026-10-14.
- The dedicated dark world map is graded pixel-for-pixel from the SAME
  original canvas, preserving all coastlines and illustration features.
- Raster compression means the image is not bit-identical to the PNG,
  but its composition is unchanged; no procedural redraw was performed.
- Both 2:1 textures remain georeferenced for the approximate route /
  city positions; no new national or city location estimators were added.
- The existing camera, node-linked panorama panning, sailing, disconnect,
  route animation, native proxy, VPN, subscription and UI layouts are
  UNCHANGED.

**GitHub CI:** feature/v1.3.1-original-watercolor-map

This is a visual-only preview; native functionality and appearance need
on-device smoke testing after CI passes.
