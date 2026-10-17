# Vela v1.8.0+34 — Oil painting preview

This is a **UI test branch** based on v1.7.0 stable. No official 1.8.0 release has been published.
It keeps the original Vela navigation, subscription, VPN, proxy and smart engine modules.

## Added
- Reference-derived hand-painted oil-map image
- 6 separate alpha PNG cloud sprites with independent 132-second cyclic wind
- Repaint boundaries, pause in background, reduced-animation support
- `--dart-define=VELA_OIL_PREVIEW=false` to return to the original watercolor atlas
- Flutter tests for cloud assets and deterministic animation

## Art limitations
The reference was a **flattened mockup**, with clouds and illustrative UI
already painted into the same pixels. Exact lossless separation is impossible
without the original layered source. This version substitutes patterned
inpainting/clone work for embedded UI; original static clouds are still visible
beneath low-opacity moving sprites. Dynamic georeferenced routes may not line
up with fixed painting outside the sample's Asia-Pacific composition.
It is for review, not for replacing v1.7.0 stable.

## Build
`flutter analyze`, `flutter test`, and CI Windows/Android builds are
triggered from this preview branch. Results must be checked in Actions.
