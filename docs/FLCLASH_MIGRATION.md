# FlClash → Vela-SHUO engine migration (work in progress)

**Status: first actual UI overlay; not a release.** Old Vela-SHUO `main`
and its APK/Windows ZIP remain untouched. The independent branch
`migration/flclash-base` is the only integration target.

## Upstream and license

- Upstream repository: https://github.com/chen08209/FlClash
- Immutable source commit: `4b59eca853778d4e7be3de26589252889c899bc5`
- License: **GNU GPL-3.0**. The full GPL-3 license lives in the upstream
  `LICENSE`, and a copy is included at this branch's root.
- Copyright stays with original FlClash, Mihomo, Rust, Vela-SHUO, and
  asset authors; preserve existing original attribution/license files.
- The complete corresponding source is the pinned upstream tree together with
  this publicly redistributable visual overlay and the upstream build inputs.
  Distribute source and notices alongside any published modified binaries.

## Scope and non-negotiable network boundary

FlClash supplies the *entire* subscription/profile management, network HTTP
overrides, protected Android VpnService, Windows proxy/TUN, startup/shutdown,
data persistence, routing, and Mihomo Go/Rust core. Do not import Vela's legacy
`lib/src/subscription`, `lib/src/android`, or `lib/src/core` at all.

The first Vela change copies only `globe.dart`, `flight_route.dart`,
`demo_connection.dart`, `vela_palettes.dart` and original globe assets,
then inserts a live-state-driven Vela heading into the upstream dashboard.
Existing upstream dashboard widgets and all networking code remain present.
The sailing animation reacts to upstream `isStartProvider`,
`coreStatusProvider` and `suspendProvider`; no fake success timer,
automatic VPN grant, or simulated network status.

## Reproduce the overlay

```bash
git clone --recursive https://github.com/chen08209/FlClash.git upstream
git -C upstream checkout 4b59eca853778d4e7be3de26589252889c899bc5
python3 scripts/migration/prepare_flclash.py \
  --vela-root . --upstream-root upstream
python3 scripts/migration/test_prepare_flclash.py
```

The script rejects an unexpected upstream commit, unrecognized dashboard
source or missing attributions instead of silently building an incompatible
hybrid. GitHub Actions checks out the pinned upstream commit and packages its
own genuine, unified Windows and Android engine.

Build requirements follow upstream: Flutter 3.47.4, Go 1.26, Rust, Android
NDK/SDK and the platform's native toolchain. `dart setup.dart ...` is the
upstream build entrypoint. Do not use Vela's old `flutter create` scaffold.

## Next milestones / release gates

1. Confirm both FlClash-based platforms compile with the overlay.
2. Windows: import HTTPS subscriptions in the user's actual network, update
   profiles, select/test nodes, start/stop system proxy and protect recovery.
3. Android: permission, VPN routing, DNS, notification and background lifecycle,
   app restart, overlay installation signing and state restore.
4. Bring over the *full* Vela-SHUO globe/layout, themes and control surfaces
   without creating a second network state machine. Do not claim finished UI.
5. Audit GPL notices, signing, source distribution, and sustained operation
   before promoting this branch into `main`.

No APK or EXE on this branch is deemed production-ready merely because its
GitHub Actions job passed.
