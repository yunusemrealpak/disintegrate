#!/bin/zsh
# Records the demo reel from a booted simulator running example/.
#
#   tool/record_demo.sh <udid> <out.mp4>
#
# Recording and gestures run inside this one process on purpose: the simulator
# keeps recording between commands, so any pause between separate invocations
# lands in the video as dead air. `idb` is warmed first because its first call
# pays for the companion's start-up.
#
# The holds are long. A dissolve is only legible while it is happening, and the
# interesting part - grain forming, drifting, thinning out - is the middle
# second, not the endpoints.
set -e

UD="${1:?usage: record_demo.sh <simulator-udid> <output.mp4>}"
OUT="${2:?usage: record_demo.sh <simulator-udid> <output.mp4>}"

# Centre of the action button, in points. Re-read it with
# `idb ui describe-all` if the layout changes.
FAB_X=195
FAB_Y=766

tap() { idb ui tap --udid $UD $1 $2 >/dev/null 2>&1 }

# A clean, deterministic status bar. Undo with:
#   xcrun simctl status_bar <udid> clear
xcrun simctl status_bar "$UD" override \
  --time "09:41" \
  --batteryState discharging --batteryLevel 100 \
  --cellularMode active --cellularBars 4 \
  --wifiMode active --wifiBars 3 \
  --dataNetwork wifi --operatorName "" >/dev/null 2>&1

idb list-targets >/dev/null 2>&1     # warm the companion

rm -f "$OUT"
xcrun simctl io "$UD" recordVideo --codec h264 --mask black --force "$OUT" >/dev/null 2>&1 &
REC=$!
sleep 1.2

sleep 1.0            # the manifest, intact
tap $FAB_X $FAB_Y    # snap
sleep 4.4            # half of them come apart and blow away
sleep 1.4            # hold on what is left
tap $FAB_X $FAB_Y    # bring them back
sleep 3.0            # reassembly is not the dissolve reversed
sleep 1.2

kill -INT $REC
wait $REC 2>/dev/null || true
echo "wrote $OUT"
