#include <flutter/runtime_effect.glsl>

uniform vec2 uResolution;
uniform float uSeconds;
uniform float uNight;
uniform vec4 uMap;      // left, top, width, height of equirect atlas
uniform float uIntensity;
uniform sampler2D uOceanMask;
out vec4 fragColor;

float hash21(vec2 p) {
  vec3 p3 = fract(vec3(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

float noise2(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  vec2 u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x),
             mix(hash21(i + vec2(0.0, 1.0)),
                 hash21(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm3(vec2 p) {
  float v = 0.0;
  float a = 0.56;
  for (int i = 0; i < 3; i++) {
    v += a * noise2(p);
    p = p * 2.07 + vec2(11.7, 4.8);
    a *= 0.48;
  }
  return v;
}

float coastalLight(vec2 point, vec2 city) {
  vec2 delta = abs(point - city);
  delta.x = min(delta.x, 1.0 - delta.x);
  return exp(-length(delta * vec2(2.0, 1.0)) * 94.0);
}

void main() {
  vec2 pos = FlutterFragCoord().xy;
  vec2 screen = pos / max(uResolution, vec2(1.0));
  // Same georeferenced camera and wrapping as the day/night map assets.
  vec2 mapUV = vec2(fract((pos.x - uMap.x) / uMap.z),
      (pos.y - uMap.y) / uMap.w);
  float sea = 0.0;
  if (mapUV.y >= 0.0 && mapUV.y <= 1.0) {
    sea = texture(uOceanMask, clamp(mapUV, 0.001, 0.999)).r;
    sea = smoothstep(0.12, 0.91, sea);
  }

  float t = uSeconds;
  // Domain-warped cloud volume: two scales move at separate slow speeds.
  vec2 cloudP = screen * vec2(3.65, 2.65)
      + vec2(t * 0.0075, -t * 0.0019);
  float bend = noise2(cloudP * 1.16 + 7.4);
  float cloud = fbm3(cloudP + vec2(bend * 0.78, bend * -0.49));
  cloud += 0.12 * fbm3(cloudP * 2.32 - vec2(t * .0031, 0.0));
  // Transparent edges and a bright scattering centre: never opaque fog.
  float fog = smoothstep(0.49, .79, cloud);
  // Do not cover the map with fog. Prefer the offshore sea, allowing only
  // a whisper of translucent mist over land silhouettes.
  fog *= (.055 + .028 * noise2(cloudP * 1.4));
  fog *= (.17 + .83 * sea) * uIntensity;

  // 12s watercolor pigment circulation inside the ocean coastline mask.
  float oceanAngle = 6.2831853 * mod(t, 12.0) / 12.0;
  vec2 tidal = vec2(cos(oceanAngle), sin(oceanAngle)) * .23;
  vec2 salt = mapUV * vec2(19.0, 10.0);
  float pigment = fbm3(salt + tidal + .38 *
      vec2(noise2(salt*.32), noise2(salt*.32 + 9.1)));
  float feather = smoothstep(.35, .73, pigment);
  float glimmer = max(0.0, sin(salt.x * 1.3 +
      salt.y * 1.95 + pigment * 7.0 + sin(oceanAngle) * 2.2));
  glimmer = pow(glimmer, 8.0) * feather;
  // Keep the original blue watercolor palette visible. Water movement is
  // pigment, not a white/light cyan replacement for the base texture.
  float seaWash = sea * (.010 + feather * .039 + glimmer * .022)
      * uIntensity;

  // Wind field is a quiet, soft ribbon of atmospheric motion rather than
  // fixed strokes. It appears and fades in a repeating 30s breathing window.
  float windPhase = mod(t, 30.0) / 30.0;
  float windGate = pow(sin(windPhase * 3.14159265), 4.0);
  vec2 flow = mapUV * vec2(7.0, 13.0) +
      vec2(-t * .057, t * .013);
  float eddy = noise2(flow * .82);
  float contour = sin(flow.y * 3.7 +
      sin(flow.x * .9 + t * .026) * 1.75 + eddy * 3.1);
  float ribbon = pow(max(0.0, contour), 14.0);
  ribbon *= smoothstep(.42, .82, noise2(flow * .42 + 3.1));
  float breeze = sea * ribbon * windGate * .075 * uIntensity;

  // Thin coastal warmth is restricted to night, 15s low-frequency pulse.
  float warm = 0.0;
  if (uNight > .5) {
    float pulse = .5 + .5 * sin(6.2831853 * mod(t, 15.0) / 15.0);
    // Flutter Windows Skia/SkSL cannot compile GLSL array initializers.
    // Evaluate the four sparse night-light sites without shader arrays.
    warm += coastalLight(mapUV, vec2(.838, .325));
    warm += coastalLight(mapUV, vec2(.889, .302));
    warm += coastalLight(mapUV, vec2(.788, .492));
    warm += coastalLight(mapUV, vec2(.295, .274));
    warm = min(warm, 1.0) * (.015 + .035 * pulse);
  }

  vec3 cloudTint = mix(vec3(.98, .99, 1.0), vec3(.68, .78, .88), uNight);
  vec3 seaTint = mix(vec3(.28, .67, .74), vec3(.39, .73, .87), uNight);
  vec3 windTint = mix(vec3(.88, .98, 1.0), vec3(.65, .88, 1.0), uNight);
  float total = fog + seaWash + breeze + warm;
  float opacity = min(total, 0.16);
  vec3 ink = cloudTint * fog + seaTint * seaWash +
      windTint * breeze + vec3(1.0, .81, .52) * warm;
  // Flutter's Skia and Impeller fragment shaders require PREMULTIPLIED
  // color. Dividing RGB by alpha caused the prior build's whiteout.
  // Scale RGB down with alpha if several effects coincide.
  float scale = total > .0001 ? opacity / total : 0.0;
  fragColor = vec4(ink * scale, opacity);
}
