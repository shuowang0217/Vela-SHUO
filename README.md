# Vela-SHUO — FlClash network engine, Vela user interface

> This branch is a migration worktree, not a finished public release.

## Product boundary

Vela-SHUO is the **only user-facing application**. Every visible screen,
navigation tab, modal, settings control, theme, globe, sailboat, notification
label and connection indicator must use Vela-SHUO's design language.
The FlClash/Mihomo project supplies **internal** subscriptions, proxy groups,
network routing, DNS, TUN/VPN, core lifecycle and platform integration.
The original Vela networking implementation is not started or copied.

A FlClash dashboard with one Vela flight card is **not** an acceptable build.

## What the migration branch currently does

- Keeps FlClash pinned to commit `4b59eca853778d4e7be3de26589252889c899bc5`.
- Builds on the upstream FlClash core and platform managers.
- Replaces the upstream application home with a Vela-owned four-tab shell.
- Reuses Vela palette tokens, sail logo, globe and connection animation.
- Connects the Vela-owned pages to FlClash's Riverpod state and actions for
  connect/disconnect, proxy group selection, delayed tests, profile import,
  profile refresh, proxy settings and Android VPN enablement.
- Preserves the original third-party GPL license and attribution.

## Not yet feature-parity or release ready

The current shell is **not** a verified 1:1 port of Vela's full old interface.
The original screens must be compared side by side; missing settings screens,
subscription edit workflows, node favorites, all smart-selection behaviors,
popups, storage semantics, desktop tray and mobile background UI still need
adaptation. Latency testing is not the same as Vela's complete smart
speed-based auto-selection system; never show fake results.

Both Windows and Android still require a clean CI build plus physical-device
testing of subscription import, core start/stop, node changes, traffic,
Windows proxy recovery and Android VPN lifecycle before any release claim.

The prior Vela-only networking implementation in `main` is historical; the
migration is done exclusively in `migration/flclash-base`. Do not merge it
into `main` or publish this branch as the completed product until parity
and testing are finished.

## Licenses and provenance

FlClash and its bundled upstream components retain their relevant
licenses; see `LICENSE`, `NOTICE-FlClash.txt` and generated
`VELA-SHUO-UPSTREAM.txt`. Interface assets retain their own attribution.
