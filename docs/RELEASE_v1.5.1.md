# Vela 1.5.1 — mobile experience and connectivity polish

Development upgrade from the frozen user-verified **Vela 1.5.0**. The
`v1.5.0` Release and existing APK are not modified.

## Changes

- Android: two adaptive node columns, with compact protocol, latency and
  download readings even on narrow portrait screens.
- Android: airport-name/traffic notification starts with VPN foreground
  connection and is removed on disconnect, revoke and service stop. Notification
  permission is requested only after pressing Connect on Android 13+.
- Separate one-click all-node latency testing from download throughput testing.
  Native FlClash/Mihomo URLTest now runs up to 16 bounded workers, using
  2.8s+1.8s candidate endpoints instead of 6s+6s+6s. Download samples still
  use the original native FlClash download method, with at most two concurrent
  1 MiB transfers; both result sets remain independent.
- Android and Windows: a monotonic HH:MM:SS connected timer appears directly
  inside the connect/disconnect card, resetting only when the real session ends.
- Geographic world-atlas sail route: Catmull–Rom cubic spline through the
  existing ocean waypoints. This eliminates sharp bends at waypoint joins;
  it does not imply nautical navigation accuracy.
- Product branding remains Vela; About Vela shows application version 1.5.1.

## Upgrade and qualification

Android package **com.shuowang.vela**, versionName **1.5.1**, versionCode
**24**, with the same immutable FlClash-Custom/SHUO permanent signing
certificate used by Vela 1.5.0. The signature check is mandatory.
Windows executable remains Vela.exe and user profile paths remain unchanged.

The feature branch builds test artifacts but **does not publish** until
promoted to release/v1.5.1. Confirm Android launch, real VPN traffic and
notification connect/disconnect; rule/global/direct behavior; 20/50+ node
double column and independent speed tests; Windows WinINet start/stop and
timer; geographic routes; About version; and 1.5.0 → 1.5.1 in-place
upgrade preserving subscriptions before publishing stable assets.
