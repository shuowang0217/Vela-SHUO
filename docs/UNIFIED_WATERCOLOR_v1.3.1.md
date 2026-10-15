# Vela v1.3.1 Unified Watercolor

Continuation of 9f05ab6931a0f212e0e3138ff3ab4b7730cf05b9.
All windows use the same map backdrop and hand-inked palette. Routing,
subscriptions, HTTPS verification, proxy restore and VPN remain unchanged.

Navigation: remove grouped dock background, make four independent circular
buttons. The same four controls appear on all desktop pages; Home is a
compact top-left shortcut outside Home. No more opaque left navigation rail.

One-click Windows system-proxy connect: no repeat confirmation modal.
The explicit user request is handled by calling the existing coordinator
whose HTTPS check, proxy state snapshot and restoration are retained.
Connection failures surface errors via a snackbar.

Screens: narrow and height-limit the very large subscription/profile hero
panels, use watercolored glass for shared cards and controls, ink-style
compass/sail/dock icons, and keep mobile VPN permission handling untouched.
