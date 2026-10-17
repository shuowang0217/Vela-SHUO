# Vela v1.7.1 — Watercolor Atlas Alignment and Motion

Preview release of Vela 1.7.1 (Android versionCode 29).

## Fixes

- Restores visible, subtle cloud and ocean animation on both Skia and Impeller
  by using a continuously repainted, inexpensive watercolor fallback in
  addition to the optional procedural GPU shader. Shader-loading errors
  no longer leave an entirely motionless atlas.
- Corrects the displayed maritime route, ship position, endpoint names,
  ocean mask and night effects against the painted coastline of the original
  watercolor artwork. Geographic node metadata is not modified.
- Retains English-only, handwritten-style labels. Idle displays CHINA;
  connected voyage displays its English origin and destination.
- Preserves the floating glass notices and untouched v1.6.0-era
  download benchmark implementation, despite this app's newer version.

## Installer identity

- Windows x64: Vela-v1.7.1-Windows-x64.zip.
- Android ARM64: Vela-v1.7.1-Android-arm64.apk.
- Android application ID remains com.shuowang.vela; build code advances to 29
  while the known permanent signing identity is preserved.
- Preview artifacts are published by GitHub Actions. They do not replace a
  frozen prior GitHub release unless a separate release is explicitly made.
