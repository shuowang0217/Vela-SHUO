# Vela v1.7.0 — Watercolor Atmosphere

A new version of the Vela Flutter host with a more restrained geographic
watercolor interface. Android version code **28** upgrades in place over the
previous stable app while keeping `com.shuowang.vela` and the pinned
release signing certificate unchanged.

## Visual changes
- Animated GPU atmosphere: soft cloud layers, geographically masked watercolor
  ocean, gentle wind, and subtle nighttime coastal highlights.
- Only **China** is labelled when disconnected; when connected, only the
  selected voyage's origin and destination appear.
- A delicate connected-only silk route highlight replaces particle glints.
- Compact translucent top-of-screen glass notices replace bottom snackbars.

## Network compatibility
- Keeps the established native FlClash/Mihomo engine and subscription flow.
- Download tests are **unchanged from the previous stable implementation**.
- Signed Android ARM64 and Windows x64 packages are built from the same source.
- The Vela application package identity and secure persisted profiles are
  preserved between upgrades.

The initial GitHub Actions packages are preview artifacts for device testing.
Release only after successful platform builds and interactive visual checks.
