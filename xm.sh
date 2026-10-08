#!/usr/bin/env bash
# ==============================================================================
# xm - Bluetooth XM headset meeting helper  (PipeWire / WirePlumber / BlueZ)
# ==============================================================================
# Fixes the classic Linux problem where Sony XM-series Bluetooth headsets
# (WH-1000XM3/XM4/XM5, WF-1000XM3/XM4/XM5 earbuds, etc.) glitch or lose their
# microphone the moment you join a Teams / Zoom / any WebRTC meeting.
#
# WHY IT BREAKS
#   - A2DP/LDAC (great music quality) has NO microphone channel.
#   - When a meeting needs the mic, the system must switch to HFP/HSP (mSBC).
#   - By default WirePlumber auto-flips to HFP the instant any app probes the
#     mic -> repeated mid-call renegotiation = "audio cuts out many times".
#   - On some headsets (notably the XM5) that switch can also die halfway,
#     leaving a silent-but-"connected" mic = "people can't hear me".
#
# THE FIX (this tool + the companion WirePlumber config 51-bt-calls.conf)
#   - The config disables the auto-switching.
#   - This command lets YOU switch ONCE, deliberately, before the meeting,
#     and provides a rescue for a dead mic link.
#
# Requires: pipewire + wireplumber + bluez (pactl, bluetoothctl), parec, python3
# Safe: only changes the Bluetooth card profile / reconnects the device.
# ==============================================================================

set -euo pipefail

APP_NAME="xm"

# ------------------------------------------------------------------------------
# Dependency check
# ------------------------------------------------------------------------------
check_deps() {
    local missing=()
    command -v pactl        >/dev/null 2>&1 || missing+=("pactl (pipewire-pulse)")
    command -v bluetoothctl >/dev/null 2>&1 || missing+=("bluetoothctl (bluez-utils)")
    command -v parec        >/dev/null 2>&1 || missing+=("parec (pipewire-pulse)")
    command -v python3      >/dev/null 2>&1 || missing+=("python3")
    if [ "${#missing[@]}" -gt 0 ]; then
        echo "Missing required commands:" >&2
        printf '  - %s\n' "${missing[@]}" >&2
        exit 1
    fi
}

# ------------------------------------------------------------------------------
# Helpers - all auto-detect the connected Bluetooth headset card / MAC
# ------------------------------------------------------------------------------
find_card() {
    local c
    c=$(pactl list cards short 2>/dev/null | awk '/bluez_card/{print $2; exit}')
    if [ -z "$c" ]; then
        echo "No Bluetooth audio card found. Is your headset connected?" >&2
        return 1
    fi
    printf '%s\n' "$c"
}

find_mac() {
    pactl list cards 2>/dev/null \
        | awk '/bluez_card/{f=1} f && /api.bluez5.address/{gsub(/"/,"",$2); print $2; exit}'
}

current_profile() {
    local card; card=$(find_card) || return 1
    pactl list cards 2>/dev/null | awk -v c="$card" '
        $0 ~ "Name: "c {f=1}
        f && /Active Profile:/ {sub(/.*Active Profile: /,""); print; exit}
    '
}

set_profile() {
    local card prof; card=$(find_card) || return 1; prof="$1"
    echo "Switching '$card' -> $prof ..."
    pactl set-card-profile "$card" "$prof" || { echo "Failed to set profile '$prof'." >&2; return 1; }
    sleep 1
    echo "Active profile now: $(current_profile)"
}

reconnect() {
    local mac; mac=$(find_mac)
    if [ -z "$mac" ]; then
        echo "Could not determine headset MAC; skipping reconnect." >&2
        return 1
    fi
    echo "Resetting Bluetooth link on $mac ..."
    bluetoothctl disconnect "$mac" >/dev/null 2>&1 || true
    sleep 2
    bluetoothctl connect    "$mac" >/dev/null 2>&1 || true
    sleep 3
    echo "Reconnected."
}


# ------------------------------------------------------------------------------
# Commands
# ------------------------------------------------------------------------------
usage() {
    cat <<EOF
$APP_NAME - Bluetooth XM headset meeting helper (Sony WH-1000XM3/XM4/XM5, WF-1000XM earbuds & similar)

Usage: $APP_NAME <command>

  call      Switch to HFP/mSBC   -> microphone + speaker BOTH work (use before a meeting)
  music     Switch to A2DP/LDAC  -> best-quality output only, no mic (use after a meeting)
  status    Show the current Bluetooth audio profile
  test      Record 5s from the mic and report LIVE / QUIET / SILENT (talk during it)
  reset     Reconnect the headset to clear a dead/silent mic link
  fix       reset + switch to 'call' profile in one shot (pre-meeting one-liner)

Typical meeting workflow:
  1) $APP_NAME call            # BEFORE joining
  2) In Teams/Zoom set  Speaker = <your headset>  and  Microphone = <your headset>
  3) $APP_NAME music           # AFTER the meeting, back to hi-fi audio
EOF
}

check_deps

cmd="${1:-}"
case "$cmd" in
    call)
        set_profile headset-head-unit
        echo "In Teams/Zoom set Speaker = your headset and Microphone = your headset."
        ;;
    music)
        set_profile a2dp-sink
        ;;
    status)
        echo "Profile: $(current_profile)"
        ;;
    test)
        prof=$(current_profile)
        case "$prof" in
            headset-head-unit|headset-head-unit-cvsd) : ;;
            *) echo "NOTE: not in a mic-capable profile ($prof). Run '$APP_NAME call' first." ;;
        esac
        src=$(pactl list sources short 2>/dev/null | awk '/bluez_input/{print $2; exit}')
        if [ -z "$src" ]; then
            echo "No headset mic source found; run '$APP_NAME call' first." >&2
            exit 1
        fi
        raw=$(mktemp /tmp/xmmic.XXXXXX.raw)
        echo "Recording 5s from $src - TALK NOW (say a few sentences)..."
        timeout 6 parec --rate=48000 --channels=1 --format=s16le -d "$src" "$raw" 2>/dev/null || true
        python3 - "$raw" <<'PY'
import sys, array
a = array.array("h"); a.frombytes(open(sys.argv[1],"rb").read())
mx = max((abs(x) for x in a), default=0)
print(f"samples={len(a)}  peak={mx}/32767")
if mx > 800:
    print("VERDICT: LIVE - microphone is working")
elif mx > 150:
    print("VERDICT: QUIET - barely hearing you; move closer / raise headset mic volume")
else:
    print("VERDICT: SILENT - run 'xm reset' then 'xm test' again")
PY
        rm -f "$raw"
        ;;
    reset)
        reconnect
        echo "Profile now: $(current_profile)"
        ;;
    fix)
        reconnect || true
        set_profile headset-head-unit
        echo "Ready for meeting (microphone + speaker on the headset)."
        ;;
    -h|--help|help)
        usage
        exit 0
        ;;
    "")
        usage
        exit 1
        ;;
    *)
        echo "Unknown command: $cmd" >&2
        echo
        usage
        exit 1
        ;;
esac
