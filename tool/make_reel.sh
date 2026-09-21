#!/bin/zsh
# Turns the raw simulator capture into the two artifacts the README ships:
#
#   tool/make_reel.sh <raw-capture.mp4>
#     -> doc/demo.mp4   540x1168 H.264   (the whole take)
#     -> doc/demo.gif   340px 12 fps     (snap + restore, holds cut)
#
# There is no ffmpeg here, so both steps go through AVFoundation:
# demo_transcode.swift rescales and re-encodes at a fixed bitrate, and
# demo_frames.swift pulls frames at an exact interval.
set -e

RAW="${1:?usage: make_reel.sh <raw-capture.mp4>}"
HERE="${0:A:h}"
ROOT="${HERE:h}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

swiftc -O -o "$WORK/transcode" "$HERE/demo_transcode.swift"
swiftc -O -o "$WORK/frames" "$HERE/demo_frames.swift"

"$WORK/transcode" "$RAW" "$ROOT/doc/demo.mp4" 540 2500

# Two segments, each cut on a settled state. Times are against doc/demo.mp4.
#   the snap | bringing them back
"$WORK/frames" "$ROOT/doc/demo.mp4" "$WORK/g0" 3.2 3.0 12 340
"$WORK/frames" "$ROOT/doc/demo.mp4" "$WORK/g1" 8.6 2.2 12 340

WORK="$WORK" OUT="$ROOT/doc/demo.gif" python3 - <<'PY'
import glob, os
from PIL import Image

work, out = os.environ["WORK"], os.environ["OUT"]
paths = [p for s in range(2) for p in sorted(glob.glob(f"{work}/g{s}/f*.png"))]
frames = [Image.open(p).convert("RGB") for p in paths]

# One palette shared by every frame: PIL can only emit inter-frame diffs when
# the palettes match, and on a screen this dark that is most of the file size.
# Dithering is off for the same reason - its noise makes every frame differ.
sample = frames[::5]
strip = Image.new("RGB", (frames[0].width, frames[0].height * len(sample)))
for i, f in enumerate(sample):
    strip.paste(f, (0, i * f.height))
palette = strip.quantize(colors=128, method=Image.MEDIANCUT)

quantised = [f.quantize(palette=palette, dither=Image.NONE) for f in frames]
quantised[0].save(out, save_all=True, append_images=quantised[1:],
                  duration=int(1000 / 12), loop=0, optimize=True, disposal=1)
print(f"{out}  {len(frames)} frames  {os.path.getsize(out) / 1e6:.1f} MB")
PY
