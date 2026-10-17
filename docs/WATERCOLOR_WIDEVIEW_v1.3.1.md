# Vela v1.3.1 Watercolor Wide View (visual-only patch)

Baseline: feature/v1.3.1-original-watercolor-map @ 58118d429fe6abe9ae3f41dc81c6bee6164796dc.
This branch makes NO changes to Vela networking, routing, subscriptions, VPN,
screen layout, glass cards, night/day watercolor texture bytes, or ship state.

Camera changes:
- Landscape map draw width: max(viewport width x 1.28, height x 2.08)
  instead of max(width x 2.2, height x 4.8). The map now shows adjacent land
  and ocean rather than zooming into China on a standard Windows window.
- On tall mobile screens, height-based coverage prevents empty map edges.
- The vertical framing is clamped to always fill the viewport; city markers,
  route paths, and ship position use the same exact camera projection.
- Horizontal country centering and dateline wrapping remain as in v1.3.1.
- Slight parchment overlay makes the image subordinate to UI glass cards.

Notes: This is an illustrated (not GIS-certified) world map. At high/northern
latitudes, the country may be biased vertically inside the view in order to
avoid exposing the texture edge. Geographic horizontal focus is unchanged.
