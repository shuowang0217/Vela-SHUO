# Unified watercolor preview — Vela v1.3.1

This branch continues from the user-approved Immersive build.
1. All four bottom-right navigation shortcuts are distinct circular
   frosted watercolor buttons, even on the proxy/config/smart/settings pages.
   A separate top-left "VELA / HOME" button returns home on desktop.
2. The old desktop navigation rail is removed entirely to reveal the world
   map. All other pages are constrained to <=885px and reserve space for
   the detached navigation controls.
3. The tall (285px) subscription and proxy hero panels shrink to ~190px.
   Card material uses unified watercolor glass with etched pen lines.
   Fonts, labels, sail identity, compass glyph and native launcher icons are
   retinted to nautical paper/ink/teal/gold.
4. Windows connection uses one click: the repeat system-proxy consent modal
   is gone by explicit user request. Existing coordinator still verifies
   remote HTTPS before setting WinINet, snapshots proxy state and restores it
   when disconnecting or exiting. Failure is reported in the home snackbar.

Android VPN permission and Android mobile navigation behavior are preserved.
All proxy protocols, subscriptions, smart engine and native bridges unchanged.
