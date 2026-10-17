# Vela v1.4.1 Android Immersive Preview

Baseline: user-approved stable v1.4.0 at 75f9d75f8250e0358a5ed686fdb42a8c3e3ce698.
The stable v1.4.0 tag, release branch and Windows binary are unchanged.

Cause: the older code routed ALL Android devices through _MobileHome, which
retained a scrolling stack of cards and a five-item Material NavigationBar.
The cosmetic shared Flutter theme did not replace this mobile experience.

Changes:
- True map-first mobile home: same watercolor day/night atlas, animated ship,
  node-focused routes, nautical VELA/SHUO logo and compact real VPN status.
- The prominent mobile connect control calls Android VpnService start/stop
  directly, checks selected node before connecting and exposes service errors.
  Android's mandatory first-use VPN authorization prompt is NOT bypassed.
- Left-bottom real traffic rates: 风速 · 上传 / 航速 · 下载 with automatic
  units; no made-up traffic when VPN is disconnected.
- Four distinct, individually frosted nautical dock buttons across all
  Android pages, with compact top-left Home shortcut.
- Space is reserved around controls in proxy/configuration/smart/settings.
- Real subscription, routing, smart tests and FlClash/Mihomo JNI backend
  are identical to v1.4.0. Windows build is skipped for this Android preview.

Version: 1.4.1+16. Subject to device visual and VPN connectivity acceptance.
