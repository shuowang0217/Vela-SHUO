# Vela World Atlas v1.3.1 development
Baseline: release/v1.3.0 @ 190caecf92741058f17aee8d96a815466bc1ad55.

Changes:
- Replace only the shared shell backdrop with a horizontally tiling world atlas.
- Use the EXISTING geographically registered day/night imagery bundled with v1.3.0.
- Focus Beijing while disconnected; follow selected node coordinates while connecting.
- Use the short wrap-around longitude path, glowing Bezier route and Vela sail mark.
- Keep existing proxy, subscription, VPN, routing, icons, and 50% glass cards.
- Return the ship to China before returning the camera on disconnect.
- Retain the old standalone VelaGlobe implementation and tests for regressions.
- Node country is estimated from its name, not verified server geography.
- Source artwork is not new 4K imagery; a separate georeferenced art upgrade remains.
- CI artifacts are development builds; native device tests are still needed.
