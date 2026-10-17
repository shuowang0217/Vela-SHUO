# Vela v1.7.2 — Hand-painted Floating Clouds

Preview release: Vela **1.7.2**, Android **versionCode 30**.

## Background
- Replaces the previous GPU fragment-shader atmosphere with six transparent,
  asymmetric, hand-painted clouds on a Flutter Canvas layer.
- Each cloud has different opacity, shape, scale and side-to-side movement.
  The 80-second repeat visibly shifts the cloud banks within a few seconds.
- Motion occurs over the original watercolor artwork but below route labels
  and the sailing vessel. No network request, image decode or shader compile
  is needed to animate clouds.

## Maritime map
- Visual origin is now **BEIJING** (116.4, 39.9), not Shanghai.
- The illustrative trip to Tokyo reaches the Bohai Bay/Yellow Sea corridor
  from Beijing before crossing toward the Japanese coast.
- Disconnected state retains **CHINA**; connected state shows English-only
  handwritten-style origin/destination names.

## Unchanged
- Original v1.6.0-compatible download-speed test logic.
- Translucent glass notifications and existing native FlClash/Mihomo core.
- Same app identity/signing identity. Windows and Android are built as
  separate v1.7.2 artifacts for testing.
