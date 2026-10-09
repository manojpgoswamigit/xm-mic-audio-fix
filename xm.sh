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
    c=$(timeout 3 pactl list cards short 2>/dev/null | awk '/bluez_card/{print $2; exit}')
    if [ -z "$c" ]; then
        echo "No Bluetooth audio card found. Is your headset connected?" >&2
        return 1
    fi
    printf '%s\n' "$c"
}

find_mac() {
    local mac
    mac=$(timeout 3 pactl list cards 2>/dev/null \
        | awk '/bluez_card/{f=1} f && /api.bluez5.address/{gsub(/"/,"",$2); print $2; exit}')
    if [ -n "$mac" ]; then
        printf '%s\n' "$mac"
        return 0
    fi
    # Fallback to paired Bluetooth devices if card is not yet in pactl
    mac=$(timeout 3 bluetoothctl devices 2>/dev/null \
        | awk '/(WH|WF)-[0-9]+XM|XM[0-9]|Sony/ {print $2; exit}')
    if [ -n "$mac" ]; then
        printf '%s\n' "$mac"
        return 0
    fi
}

current_profile() {
    local card; card=$(find_card) || return 1
    timeout 3 pactl list cards 2>/dev/null | awk -v c="$card" '
        $0 ~ "Name: "c {f=1}
        f && /Active Profile:/ {sub(/.*Active Profile: /,""); print; exit}
    '
}

set_profile() {
    local card prof; card=$(find_card) || return 1; prof="$1"
    echo "Switching '$card' -> $prof ..."
    timeout 5 pactl set-card-profile "$card" "$prof" || { echo "Failed to set profile '$prof'." >&2; return 1; }
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
    timeout 6 bluetoothctl disconnect "$mac" >/dev/null 2>&1 || true
    sleep 2
    timeout 12 bluetoothctl connect    "$mac" >/dev/null 2>&1 || true
    # Wait up to 5s for the audio card to settle in PipeWire
    local i=0
    while [ $i -lt 10 ]; do
        if timeout 1 pactl list cards short 2>/dev/null | grep -q 'bluez_card'; then
            break
        fi
        sleep 0.5
        i=$((i+1))
    done
    echo "Reconnected."
}


# ------------------------------------------------------------------------------
# Machine-readable status (used by the KDE Plasma widget).
#   Prints EXACTLY ONE token and ALWAYS exits 0, so the widget can never end up
#   parsing an error message, a stack trace or a half-written line:
#     a2dp   - headset connected, hi-fi profile (music, no mic)
#     hfp    - headset connected, hands-free profile (mic + speaker)
#     off    - headset connected, audio profile standby / off
#     none   - no Bluetooth audio card (headset off / disconnected)
#     error  - dependency missing or the stack could not be queried
# Must stay fast: it is polled every couple of seconds by the panel applet.
# ------------------------------------------------------------------------------
print_machine_status() {
    command -v pactl >/dev/null 2>&1 || { echo "error"; return 0; }

    local card
    card=$(find_card 2>/dev/null) || card=""
    if [ -z "$card" ]; then
        # Card not in pactl. Check if headset is connected in bluetoothctl:
        local mac; mac=$(find_mac 2>/dev/null) || mac=""
        if [ -n "$mac" ]; then
            local conn
            conn=$(timeout 2 bluetoothctl info "$mac" 2>/dev/null | awk '/Connected:/{print $2}')
            if [ "$conn" = "yes" ]; then
                echo "off"
                return 0
            fi
        fi
        echo "none"
        return 0
    fi

    local prof
    prof=$(timeout 2 pactl list cards 2>/dev/null | awk -v c="$card" '
        $0 ~ "Name: "c {f=1}
        f && /Active Profile:/ {sub(/.*Active Profile: /,""); print; exit}
    ')

    case "$prof" in
        headset-head-unit*) echo "hfp"  ;;
        a2dp-sink*)         echo "a2dp" ;;
        off)                echo "off"  ;;
        *)                  echo "error";;
    esac
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
           (add --machine to print one bare token: a2dp | hfp | none | error,
            used by the KDE Plasma widget)
  test      Record 5s from the mic and report LIVE / QUIET / SILENT (talk during it)
  reset     Reconnect the headset to clear a dead/silent mic link
  fix       reset + switch to 'call' profile in one shot (pre-meeting one-liner)
  defaults-reset
            Remove the WirePlumber drop-in and restore automatic profile switching

Typical meeting workflow:
  1) $APP_NAME call            # BEFORE joining
  2) In Teams/Zoom set  Speaker = <your headset>  and  Microphone = <your headset>
  3) $APP_NAME music           # AFTER the meeting, back to hi-fi audio
EOF
}

cmd="${1:-}"

# --- Machine-readable status is handled BEFORE the dependency gate so it never
# --- exits non-zero on a machine that simply lacks the audio stack. It reports
# --- 'error' itself instead, and always prints exactly one token on stdout.
if [ "$cmd" = "status" ] && [ "${2:-}" = "--machine" ]; then
    print_machine_status
    exit 0
fi

check_deps

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
        # Wait up to 5s for the PulseAudio card to settle in PipeWire after reconnect
        local i=0
        while [ $i -lt 10 ]; do
            if timeout 1 pactl list cards short 2>/dev/null | grep -q 'bluez_card'; then
                break
            fi
            sleep 0.5
            i=$((i+1))
        done
        set_profile headset-head-unit
        echo "Ready for meeting (microphone + speaker on the headset)."
        ;;
    defaults-reset)
        # Remove the WirePlumber drop-in and let Plasma's default automatic
        # A2DP/HFP switching take over again. Fully reversible with install.sh.
        conf="${HOME}/.config/wireplumber/wireplumber.conf.d/51-bt-calls.conf"
        if [ -f "$conf" ]; then
            rm -f "$conf"
            echo "Removed ${conf}"
        else
            echo "The xm WirePlumber drop-in was not installed."
        fi
        echo "Restarting WirePlumber (auto-switching back on)..."
        if systemctl --user restart wireplumber 2>/dev/null; then
            echo "WirePlumber restarted: automatic A2DP/HFP switching is on again."
        else
            echo "Could not restart WirePlumber automatically; run:" >&2
            echo "  systemctl --user restart wireplumber" >&2
        fi
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
