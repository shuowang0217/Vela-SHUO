# Vela v1.3.3 — product-grade sailing journal
Baseline: v1.3.2 successful build a156e7f6864eff82dab99905e5184e26b141578f.
The user-approved screen mockups define the VISUAL SYSTEM, never merely a palette.
The app remains genuine Flutter controls and backend, not a static screenshot.

## Major upgrades
- Georeferenced coastline source: assets/maps/world_110m.json.
- New 2400x1200 light watercolor map and midnight nautical atlas rendered
  at build time. No source satellite image is used by the generator.
- Generated paper grain for all cards and navigation rail, with irregular
  engraved pen borders, postcard stamps and ink lighthouse.
- Every existing palette recolors ink and watercolors, but keeps one journal
  component language across the full app; the "journal" palette is now named
  "羊皮纸·海盐青" to clarify its role as only one color option.
- Retains the working real Windows/Android proxy UI and state projection.
- Animated routes become dotted ink trajectories and city names use English
  travel-journal typography. The sailing marker and geography still animate
  from the original connection controller. Destinations are guessed from
  node names and remain illustrative rather than verified IP geolocations.

## Build and verification
python3 -m pip install pillow
python3 scripts/generate_world_watercolor.py
flutter pub get
flutter analyze
flutter test
flutter build windows --release
(also Android arm64 APK in GitHub Actions)
