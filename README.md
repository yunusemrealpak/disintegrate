# disintegrate

[![license](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![flutter](https://img.shields.io/badge/flutter-%E2%89%A5%203.41-blue.svg)](https://flutter.dev)
[![renderer](https://img.shields.io/badge/renderer-Impeller-7952B3.svg)](https://docs.flutter.dev/perf/impeller)

Thanos-snap style disintegration for **any Flutter widget** — the whole thing is
one GPU fragment shader, not a particle system on the CPU.

<p align="center">
  <img src="https://raw.githubusercontent.com/yunusemrealpak/disintegrate/main/doc/demo.gif"
       width="300" alt="A list of cards turning to dust and blowing away, then coming back">
</p>

```dart
Disintegrate(
  visible: _stillHere,
  onDissolved: () => setState(() => _list.remove(item)),
  child: ListTile(title: Text('…')),
)
```

## Install

```yaml
dependencies:
  disintegrate: ^0.1.0
```

No setup beyond that — the shader ships with the package.

## Two ways to drive it

**Let the widget own the animation.** Flip `visible` and it takes care of itself:

```dart
Disintegrate(
  visible: _visible,
  duration: const Duration(milliseconds: 1100),
  drift: const Offset(30, -46),      // where the dust goes, and how far
  scatter: 1.6,                      // how widely the grains fan out
  spread: const EdgeInsets.fromLTRB(18, 60, 60, 10),
  onDissolved: _remove,
  child: card,
)
```

**Or drive it yourself**, from an animation you already have. This is the one to
use when several widgets go at once, because a screenful of dissolves should
cost one animation, not one per widget:

```dart
DisintegrateEffect(
  progress: _progressFor(index),   // your own 0..1
  seed: index * 31.7,              // so they do not dissolve in lockstep
  child: card,
)
```

The example app snaps half a list from a single `AnimationController`: each row
reads its own slice of it, offset by a per-row delay.

## How it works

### Particles you never draw

A disintegration is thousands of grains. Drawing thousands of anything per frame
is how this effect usually dies, so nothing here is drawn: the shader runs
**backwards**. For every output pixel it works out which grain that pixel
belongs to, where that grain started, and samples the widget there:

```glsl
vec2 cell = floor(frag / uCell);         // which grain
float rnd  = hash21(cell + uSeed);       // its own random life
vec2 disp  = uDrift * local * local;     // how far it has flown by now
fragColor  = texture(uTexture, toUv(frag - disp)) * fade * grain;
```

The cost is the surface area, not the grain count. Turning `particleSize` down
from 3 to 1 multiplies the number of grains by nine and costs nothing.

### The widget is the texture

`ImageFilter.shader` (Flutter 3.41+) hands the shader whatever the child painted
as a `sampler2D`, so the effect applies to *any* widget — a `ListTile`, a chart,
a video, a whole page — without knowing anything about it. Two uniforms are set
by the engine and must come first in the shader:

```glsl
uniform vec2 uSize;          // filter input size  — engine
uniform sampler2D uTexture;  // the widget itself  — engine
uniform float uProgress;     // yours, from here down
```

### Grains have to shrink, not just fade

A dissolve that only fades holes into the surface reads as a glitch. Each cell
is masked to a dot that shrinks as it travels, so the surface comes apart into
grains rather than eroding in place:

```glsl
vec2 withinCell = fract((frag - disp) / uCell) - 0.5;
float radius = mix(0.72, 0.05, local);
float grain  = 1.0 - smoothstep(radius * 0.55, radius, length(withinCell));
```

The mask is faded in over the first 20% of the cell's life. Without that, a
widget at `progress = 0.01` would suddenly wear a halftone screen.

### Grains need their own heading, too

Moving every grain along the same vector is a translation with holes punched in
it, however fine the grain is. Each cell gets its own heading, rotated out of
`drift` by up to `scatter` radians, and its own speed:

```glsl
float angle = (rndHeading - 0.5) * uScatter;
vec2 heading = rotate(dir, angle);
float speed = mix(0.4, 1.8, rndSpeed);
vec2 disp = heading * length(drift) * speed * travel;
```

`travel` eases *out* — `1 - (1 - local)²`. Grains break away quickly and then
coast, which is what letting go of something looks like; accelerating the whole
way looks like the surface is being pushed.

### Dust needs somewhere to go

A shader filter can only paint inside the surface it is handed, so by default
the dust is cut off at the widget's own edge and the drift has nowhere to go.
`spread` adds room around the child:

```dart
spread: const EdgeInsets.fromLTRB(6, 40, 44, 6),   // matches a drift of (52, -58)
```

It is padding, so it does take layout space. The usual move is to spend the gap
the layout already had between items, which is what the example does — the
cards give up their margins and the list looks unchanged.

### The parameters, and what each one is for

| | | |
| --- | --- | --- |
| `progress` | `0..1` | 0 is untouched, 1 is gone |
| `drift` | `Offset` | direction and distance of the flight, in logical pixels |
| `particleSize` | logical px | small reads as dust, large as debris |
| `sweep` | `0..1` | 0 dissolves everything at once, 1 sweeps it along `drift` |
| `turbulence` | logical px | how far grains wander sideways |
| `scatter` | radians | how widely headings fan out from `drift` |
| `seed` | `double` | which grains leave first |
| `spread` | `EdgeInsets` | room for the dust, see above |

Distances are authored in logical pixels and converted to physical ones before
they reach the shader, so a grain is the same size on every device instead of
scaling with the screen.

### What it costs when nothing is happening

At `progress == 0` the widget returns its child untouched: no filter, no shader,
no extra layer. At `progress == 1` it keeps the child laid out and mounted but
stops painting it, so scroll positions and state survive a full dissolve. There
is a test for both.

### The trap that cost the most time

`ImageFilter.shader` compares equal when it wraps the same `FragmentShader`,
and `ImageFiltered` skips repainting when its filter has not changed. Mutating
one shader's uniforms in place therefore updates them correctly and **never
reaches the screen**: the widget sits there intact, and then a scroll — or any
unrelated repaint of the subtree — makes the whole dissolve appear at once.

The fix is to hand over a different instance each time. This package keeps two
shaders and alternates between them, so there is no per-frame allocation and no
question of disposing something a layer still references.

## Requirements

Shader-backed image filters are an **Impeller** feature, which means Flutter
3.41 or newer, and iOS, Android or macOS. On anything else — including web —
the widgets fall back to an opacity fade: not the effect, but the same start and
the same end, so nothing jumps. `DisintegrateProgram.isSupported` tells you
which one you are getting.

Call `DisintegrateProgram.preload()` during start-up. Compiling the program
takes a moment, and without it the first dissolve quietly falls back.

## The example

```bash
cd example
flutter run
```

A crew manifest with a **SNAP** button. Half of them go, on one timeline, and
come back on another — reassembly is not the dissolve played backwards. The
portraits are generated images, not photographs of anyone.

The reel above is reproducible: `tool/record_demo.sh <udid> <out.mp4>` drives
the capture in a single process, and `tool/make_reel.sh` turns it into the GIF
and the MP4 in `doc/`.

## License

MIT — see [LICENSE](LICENSE).
