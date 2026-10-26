#!/usr/bin/env bash
# =============================================================================
#  Live mic waveform contract
# =============================================================================
#  `xm test --json --live-file PATH` must publish real 100 ms levels while it
#  is still recording, not only after the five second sample is complete.
#  The widget polls PATH for those levels and draws them as a live waveform.
#
#  This test uses fake pactl/parec binaries so it is deterministic and does not
#  need a Bluetooth headset.
# =============================================================================

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/xm-live-test.XXXXXX")
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/bin"

cat > "$tmp/bin/pactl" <<'SH'
#!/usr/bin/env bash
case "${1:-}" in
    info)
        exit 0
        ;;
    list)
        case "${2:-}" in
            sources)
                echo "1	bluez_input.80:99:E7:36:CB:CA	PipeWire	record	RUNNING"
                ;;
            cards)
                if [ "${3:-}" = "short" ]; then
                    echo "1	bluez_card.80_99_E7_36_CB_CA	bluez5	module-bluez5-device"
                else
                    cat <<'EOF'
Card #1
	Name: bluez_card.80_99_E7_36_CB_CA
	Profiles:
		headset-head-unit: HFP
		a2dp-sink: A2DP
	Active Profile: headset-head-unit
EOF
                fi
                ;;
        esac
        ;;
esac
SH

cat > "$tmp/bin/parec" <<'PY'
#!/usr/bin/env python3
# Emit five seconds of test speech, one 100 ms chunk at a time. Real parec
# buffers about two seconds unless it is asked for low latency, which makes a
# "live" waveform arrive almost entirely at the end. Mirror that here so the
# regression test fails if xm.sh forgets --latency-msec.
import math
import struct
import sys
import time

low_latency = any(arg.startswith("--latency-msec") for arg in sys.argv[1:])
if not low_latency:
    time.sleep(2.0)

for chunk in range(50):
    amplitude = 2400 if chunk % 2 == 0 else 1200
    data = bytearray()
    for n in range(4800):
        sample = int(amplitude * math.sin(2 * math.pi * 440 * n / 48000))
        data += struct.pack("<h", sample)
    sys.stdout.buffer.write(data)
    sys.stdout.buffer.flush()
    time.sleep(0.1)
PY

chmod +x "$tmp/bin/pactl" "$tmp/bin/parec"

live="$tmp/live.txt"
result="$tmp/result.json"
err="$tmp/stderr.txt"

PATH="$tmp/bin:$PATH" "$repo_root/xm.sh" test --json --live-file "$live" \
    >"$result" 2>"$err" &
pid=$!

# The command must still be recording when several real levels appear. Give
# parec one second of startup slack, then demand evidence that it is streaming
# rather than buffering the whole test until the end.
levels=0
for _ in $(seq 1 12); do
    if [ -f "$live" ]; then
        levels=$(wc -l < "$live")
    fi
    if [ "$levels" -ge 3 ]; then
        break
    fi
    sleep 0.1
done

if [ "$levels" -lt 3 ]; then
    echo "FAIL: expected live levels within 1.2s of recording, got $levels" >&2
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    cat "$err" >&2
    exit 1
fi

if ! kill -0 "$pid" 2>/dev/null; then
    echo "FAIL: test finished before publishing live levels" >&2
    cat "$err" >&2
    exit 1
fi

wait "$pid"

python3 - "$result" "$live" <<'PY'
import json
import sys

result_path, live_path = sys.argv[1], sys.argv[2]

with open(result_path, encoding="utf-8") as fh:
    result = json.load(fh)
assert result["ok"] is True, result
assert len(result["levels"]) == 50, f"expected 50 final bars, got {len(result['levels'])}"

with open(live_path, encoding="utf-8") as fh:
    live = [float(line) for line in fh if line.strip()]

assert len(live) >= 50, f"expected 50 live levels, got {len(live)}"
assert all(0.0 <= value <= 1.0 for value in live), live
assert max(live) - min(live) > 0.05, f"live levels do not move: {live[:8]}"
print(f"PASS: {len(live)} live levels, {len(result['levels'])} final bars")
PY
