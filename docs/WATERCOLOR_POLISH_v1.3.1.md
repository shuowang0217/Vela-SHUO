# v1.3.1 Watercolor Polish (UI-only preview)

Derived from feature/v1.3.1-watercolor-wideview at 556c06c0dabfd7d5b296bbaf54bb7b3fffdab0f7.

Four requested fixes:
1. Eliminate the dateline tile seam by blending the existing watercolor
   image's left/right pixels across a ~4.5% boundary band. The CI calls
   scripts/prepare_watercolor_atlas.py before flutter asset bundling. A 1.3px
   draw overlap also prevents thin GPU tile-edge artifacts.
2. Larger 46px sail mark, stronger 4px route and 13-15pt city labels.
   Decorative English labels now stay visible over the map.
3. Night colors are NOT just a dark filter: geographically aligned existing
   earth_night_lights.png radiance is colorized to warm golden city lights,
   layered with a soft bloom over the original night-watercolor art.
4. Desktop: compact connection controls and routing mode, smaller metrics
   placed further down to reveal more of the artwork. Mobile retains its
   existing responsive ListView design.

The networking, subscription, VPN, proxy and connection state logic is
identical to the v1.3.1 preview. Source watercolor assets are preserved;
the packaging script prepares build-workspace copies on each runner.
