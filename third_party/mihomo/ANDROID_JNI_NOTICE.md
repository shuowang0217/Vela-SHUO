# Android Mihomo JNI bundle (GPL-3.0)

The Android ARM64 VPN Beta embeds
[oviron/libmihomo-android](https://github.com/oviron/libmihomo-android)
v0.3.7 as a pinned release AAR.

SHA-256:
`e9582440766f7e37f8f6b23344bee35d73e66e7e7a9fc3b90da5631f0fd19f24`

The library embeds Mihomo/Clash-Meta and JNI hooks, and both the library and
upstream Mihomo are licensed GPL-3.0.

Sources and corresponding notices:
- https://github.com/oviron/libmihomo-android/tree/v0.3.7
- https://github.com/oviron/libmihomo-android/blob/v0.3.7/LICENSE
- https://github.com/MetaCubeX/mihomo
- https://github.com/MetaCubeX/mihomo/blob/main/LICENSE

The Vela Android app's native integration and Flutter source files are part
of this repository, under `native/android` and `lib/src/android`. A GPL
licensing review is required before commercial redistribution. Never treat
the embedded AAR as MIT-licensed or claim it is a proprietary component.
