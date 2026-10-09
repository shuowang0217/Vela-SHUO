# Vela-SHUO roadmap

- **0.1-A:** Independent Flutter source, responsive four-page shell, theme preference, Windows portable EXE ZIP and Android ARM64 debug DEV APK built by GitHub Actions.
- **0.1-B:** Original ocean-blue globe dashboard matching the approved visual reference; real geographic Earth projection, minimal sail markers, route animation, demo node switching, responsive desktop/mobile design. UI simulation only.
- **0.1-C:** Redacted local diagnostics, offline startup and data corruption recovery.
- **Windows-first (2026-10-09):** Freeze Android work and CI builds; finish and validate the Windows EXE before resuming Android.
- **0.1-D:** Windows installer, signed/versioned Windows release process. Android permanent signing is postponed until after Windows stable release.
- **0.2:** Securely integrate a license-reviewed proxy engine and real connection lifecycle.
- **0.3:** Vela Smart Engine: throughput probes, rolling score, stable switching and fault recovery.

Never overwrite the stable `FlClash-Custom` packages.

## Delivery order

**Windows EXE stable first → Android adaptation, release signing, device verification → Android APK stable.** The original Vela UI remains responsive in Flutter, but the Android-specific VPN, permission and lifecycle work cannot be treated as automatically validated by Windows testing.
