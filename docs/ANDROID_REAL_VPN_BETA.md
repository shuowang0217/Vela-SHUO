# Android Mihomo Real VPN Beta

This feature uses the GPL-3.0 Mihomo core via the GPL-3.0 JNI wrapper
[oviron/libmihomo-android](https://github.com/oviron/libmihomo-android)
and the Android platform `VpnService`. The JNI wrapper is **pinned** to
`v0.3.7` with SHA-256 `e9582440766f7e37f8f6b23344bee35d73e66e7e7a9fc3b90da5631f0fd19f24`.
Only official release artifacts with the pinned digest are allowed into CI.

## Architecture

- Flutter parses user-supplied subscriptions into an allowlisted set of
  proxies and creates a JSON profile without user-defined TUN or API listeners.
- Native `MainActivity` requires explicit Android `VpnService.prepare()`
  system consent. It hands profile data to the internal app-private cache,
  not an exported IPC `Intent`.
- A foreground `VpnService` calls `Clash.quickSetup` (Mihomo embedded JNI),
  creates an IPv4 + IPv6 TUN interface via `VpnService.Builder`, and passes
  its file descriptor to `Clash.startTUN` with a socket `protect` callback.
- Android TUN routes 0/0 and ::/0 through Mihomo. IPv6 is not supported for
  proxy destinations yet and will be blocked rather than sent directly.
  DNS routes to Mihomo DNS fake-IP on 198.18.0.2.
- Only after genuine public HTTPS probing succeeds does the native service
  broadcast `connected`; opening a dialog or starting a foreground service
  alone never counts as connected.
- Stop, Android VPN permission revocation or error tears down the TUN,
  releases native resources, and deletes the temporary plaintext profile.
  After an ungraceful process kill, the private cached profile can remain
  until next startup/cache cleanup; do not treat it as encrypted persistent
  storage. The optional encrypted subscription Vault is independent.

## Limitations

This is a **beta**, not a fully field-validated production VPN. CI can test
Flutter behavior, build Android ARM64 binaries, and verify library embedding,
but a physical Android device and real provider nodes are required to verify
end-to-end VPN routing, DNS, mobile network switching, lock screen/background,
IPv6 policy, app standby/battery restrictions, and vendor-specific crashes.
Do not claim real-world connectivity without that test.

The app requires the Android user to accept the VPN permission and allow
the foreground service to operate. Android can revoke the VPN permission.
A notification action stops the VPN without opening the Flutter UI.
When the app is in the background, the foreground service remains alive
unless the OS or user stops it. There is no auto-connect after reboot or
automatic VPN restart after process death.

Current Beta uses package ID `com.shuowang.vela.vpn.beta`, distinct from
the original read-only preview `com.shuowang.vela.preview`.

## GPL-3.0 distribution

Mihomo and the JNI wrapper are GPL-3.0. A distributable combined Android app
must satisfy GPL-3.0 corresponding-source, license text and notice obligations.
See the JNI wrapper upstream license and source linked above, as well as
[MetaCubeX/mihomo](https://github.com/MetaCubeX/mihomo).
This project's source for the Android bridge is in `native/android/`.
Do not redistribute as a proprietary closed-source app without a license review.

## Next tests

On a real Android ARM64 device, choose a known-working subscribed node,
tap “授权并连接真实 VPN”, approve Android VPN consent, confirm a key icon and
notification, verify public IP via browser, open HTTPS sites, test DNS,
disconnect, force-stop and reopen, change Wi-Fi/cellular and rotate screen.
