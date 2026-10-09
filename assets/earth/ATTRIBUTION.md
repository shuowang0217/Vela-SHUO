# Geographic texture attribution (UI prototype)

The visual globe uses third-party Earth imagery to avoid unrealistic flat land
shapes. These are media assets, not code written by SHUO.

- \`assets/earth/earth_day.jpg\`: Three.js \`earth_atmos_2048.jpg\`.
- \`assets/earth/earth_night_lights.png\`: Three.js \`earth_lights_2048.png\`.
- Source: https://github.com/mrdoob/three.js/tree/dev/examples/textures/planets
- Retrieved: 2026-10-09.
- The underlying Earth observation imagery is NASA-derived. The image files
  were mirrored into this private prototype; retain this acknowledgement and
  review exact upstream media licensing before public distribution.
- The night lights are illustrative geographic imagery, not the real-time
  brightness of cities and not user network usage.
- Original Vela-SHUO globe mesh, geographic rotation, raised Bezier flight
  trajectory, animated sail marker and application UI are authored in this repo.

No runtime network request is required to show the globe. The imagery is
bundled in the Windows application and the interface remains available offline.
