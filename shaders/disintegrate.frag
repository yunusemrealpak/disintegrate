#version 460 core

#include <flutter/runtime_effect.glsl>

// Engine-provided uniforms. The engine writes the size of the filter input into
// the first vec2 and binds the input texture to the first sampler2D, so these
// two must stay at the top and must not be set from Dart.
uniform vec2 uSize;
uniform sampler2D uTexture;

// Authored uniforms. Every distance below is in physical pixels; the Dart side
// multiplies by the device pixel ratio before setting them. Adding one here
// means updating _authoredFloats on the Dart side.
uniform float uProgress;   // 0 = intact, 1 = fully gone
uniform vec2 uDrift;       // where the dust travels, and how far
uniform float uCell;       // particle size
uniform float uSweep;      // 0 = the whole surface goes at once, 1 = full sweep
uniform float uTurbulence; // sideways wander
uniform float uScatter;    // how widely headings fan out, in radians
uniform float uSeed;

out vec4 fragColor;

float hash21(vec2 p) {
  p = fract(p * vec2(127.1, 311.7));
  p += dot(p, p + 42.35);
  return fract(p.x * p.y);
}

vec2 toUv(vec2 px) {
  vec2 uv = px / uSize;
#ifdef IMPELLER_TARGET_OPENGLES
  // Sampling the filter input is y-flipped on the GLES backend.
  uv.y = 1.0 - uv.y;
#endif
  return uv;
}

void main() {
  vec2 frag = FlutterFragCoord().xy;

  // The effect is backwards on purpose. Drawing N particles would mean N draw
  // calls; instead every fragment works out which particle it belongs to and
  // where that particle came from, so the cost is the surface area and not the
  // particle count.
  vec2 cell = floor(frag / max(uCell, 1.0));
  float rndDelay = hash21(cell + uSeed);
  float rndHeading = hash21(cell + uSeed + 31.7);
  float rndSpeed = hash21(cell + uSeed + 91.3);
  float rndWobble = hash21(cell + uSeed + 17.0) * 2.0 - 1.0;

  vec2 drift = length(uDrift) > 0.0 ? uDrift : vec2(0.0, -1.0);
  vec2 dir = normalize(drift);

  // Cells further along the drift direction leave first. That head start is
  // what makes it read as something being carried away rather than a fade.
  float along = clamp(dot(frag / uSize, dir) * 0.5 + 0.5, 0.0, 1.0);
  float delay = clamp((along * 0.75 + rndDelay * 0.25) * uSweep, 0.0, 0.985);
  float local = clamp((uProgress - delay) / max(1e-3, 1.0 - delay), 0.0, 1.0);

  // Grains break away quickly and then coast. Accelerating instead makes the
  // surface look pushed rather than let go of.
  float travel = 1.0 - (1.0 - local) * (1.0 - local);

  // Each grain gets its own heading and its own speed. Moving them all by the
  // same vector is a translation with holes punched in it, however fine the
  // grain is - the spread is what turns it into scatter.
  float angle = (rndHeading - 0.5) * uScatter;
  float ca = cos(angle);
  float sa = sin(angle);
  vec2 heading = vec2(dir.x * ca - dir.y * sa, dir.x * sa + dir.y * ca);
  float speed = mix(0.4, 1.8, rndSpeed);

  vec2 disp = heading * length(drift) * speed * travel;
  disp += vec2(-heading.y, heading.x) * rndWobble * uTurbulence * travel;

  vec2 uv = toUv(frag - disp);
  if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
    fragColor = vec4(0.0);
    return;
  }

  // Each cell shrinks to a dot as it travels. Without this the surface only
  // develops holes - it erodes in place instead of coming apart into grains,
  // which is the difference between a glitch and dust.
  vec2 withinCell = fract((frag - disp) / max(uCell, 1.0)) - 0.5;
  float radius = mix(0.78, 0.02, travel);
  float grain = 1.0 - smoothstep(radius * 0.5, radius, length(withinCell));
  // At the very start the grain mask must be invisible, or an untouched widget
  // would suddenly wear a halftone screen.
  grain = mix(1.0, grain, smoothstep(0.0, 0.18, local));

  // A long tail: the grains are still out there, getting thinner, for most of
  // the flight. Cutting them off early is what made this read as a wipe.
  float fade = 1.0 - smoothstep(0.3, 1.0, local);

  // The sampler hands back premultiplied alpha, so scaling the whole texel
  // keeps it premultiplied, which is what the engine expects back.
  fragColor = texture(uTexture, uv) * fade * grain;
}
