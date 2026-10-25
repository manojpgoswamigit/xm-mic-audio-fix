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
WP_CONF="${HOME}/.config/wireplumber/wireplumber.conf.d/51-bt-calls.conf"

# ------------------------------------------------------------------------------
# Dependency helpers
# ------------------------------------------------------------------------------
have() { command -v "$1" >/dev/null 2>&1; }

require() {
    local missing=() c
    for c in "$@"; do
        have "$c" || missing+=("$c")
    done
    if [ "${#missing[@]}" -gt 0 ]; then
        echo "Missing required commands: ${missing[*]}" >&2
        echo "Install the PipeWire/BlueZ tools for your distribution (see README)." >&2
        exit 1
    fi
}

json_str() {
    # Escape a value for a single-line JSON string.
    local s="$1"
    s=${s//\\/\\\\}
    s=${s//\"/\\\"}
    s=${s//$'\n'/ }
    s=${s//$'\r'/ }
    printf '%s' "$s"
}

# ------------------------------------------------------------------------------
# Helpers - all auto-detect the connected Bluetooth headset card / MAC
# ------------------------------------------------------------------------------
find_card() {
    have pactl || return 1
    local c
    c=$(timeout 3 pactl list cards short 2>/dev/null | awk '/bluez_card/{print $2; exit}' || true)
    if [ -z "$c" ]; then
        echo "No Bluetooth audio card found. Is your headset connected?" >&2
        return 1
    fi
    printf '%s\n' "$c"
}

find_mac() {
    local mac=""
    if have pactl; then
        mac=$(timeout 3 pactl list cards 2>/dev/null \
            | awk '/bluez_card/{f=1} f && /api.bluez5.address/ {sub(/.*= *"/,""); sub(/".*/,""); print; exit}' || true)
    fi
    if [ -n "$mac" ]; then
        printf '%s\n' "$mac"
        return 0
    fi
    # Fallback to paired Bluetooth devices if card is not yet in pactl
    if have bluetoothctl; then
        mac=$(timeout 3 bluetoothctl devices 2>/dev/null \
            | awk '/(WH|WF)-[0-9]+XM|XM[0-9]|Sony/ {print $2; exit}' || true)
        if [ -n "$mac" ]; then
            printf '%s\n' "$mac"
            return 0
        fi
    fi
    return 0
}

current_profile() {
    local card; card=$(find_card) || return 1
    timeout 3 pactl list cards 2>/dev/null | awk -v c="$card" '
        $0 ~ "Name: "c {f=1}
        f && /Active Profile:/ {sub(/.*Active Profile: /,""); print; exit}
    ' || true
}

# Human name of the headset, from BlueZ when possible, else from the card.
device_name() {
    local mac name card
    mac=$(find_mac 2>/dev/null) || mac=""
    if [ -n "$mac" ] && have bluetoothctl; then
        name=$(timeout 2 bluetoothctl info "$mac" 2>/dev/null \
            | awk -F': ' '/^[[:space:]]*Name:/{print $2; exit}' || true)
        if [ -n "$name" ]; then
            printf '%s\n' "$name"
            return 0
        fi
    fi
    card=$(find_card 2>/dev/null) || card=""
    if [ -n "$card" ]; then
        timeout 2 pactl list cards 2>/dev/null | awk -v c="$card" '
            $0 ~ "Name: "c {f=1}
            f && /device.description/ {sub(/.*= "/,""); sub(/".*/,""); print; exit}
        ' || true
    fi
    return 0
}

# Codec of the active profile (LDAC, AAC, SBC, SBC-XQ, mSBC, CVSD ...).
active_codec() {
    local card prof
    card=$(find_card 2>/dev/null) || return 0
    prof=$(current_profile 2>/dev/null) || return 0
    [ -n "$prof" ] || return 0
    timeout 2 pactl list cards 2>/dev/null | awk -v c="$card" -v p="$prof" '
        $0 ~ "Name: "c {f=1}
        f && $0 ~ "^[ \t]*"p":" {
            sub(/^[ \t]*/,"")
            if (match($0, /codec [^),]*/)) {
                s = substr($0, RSTART + 6, RLENGTH - 6)
                print s
            }
            exit
        }
    ' || true
}

mic_source() {
    have pactl || return 0
    timeout 3 pactl list sources short 2>/dev/null | awk '/bluez_input/{print $2; exit}' || true
}

device_connected() {
    have bluetoothctl || return 0
    local mac
    mac=$(find_mac 2>/dev/null) || mac=""
    [ -n "$mac" ] || return 0
    timeout 2 bluetoothctl info "$mac" 2>/dev/null | awk '/Connected:/{print $2; exit}' || true
}

wait_for_mic_source() {
    local tries="${1:-8}" delay="${2:-0.5}" i=0
    while [ "$i" -lt "$tries" ]; do
        if [ -n "$(mic_source)" ]; then
            return 0
        fi
        sleep "$delay"
        i=$((i+1))
    done
    return 1
}

list_card_profiles() {
    local card; card=$(find_card 2>/dev/null) || return 0
    timeout 2 pactl list cards 2>/dev/null | awk -v c="$card" '
        $0 ~ "Name: "c {f=1}
        f && /^[ \t]*Profiles:/ {inp=1; next}
        f && /Active Profile:/ {inp=0}
        f && inp && /^[ \t]+[a-z0-9_-]+: / {
            sub(/^[ \t]+/,""); sub(/:.*/,""); print "  " $0
        }
    ' || true
}

# Best-effort: BlueZ only exports Battery1 when the headset advertises it.
battery_level() {
    local mac="$1" v path
    [ -n "$mac" ] || return 0
    if have bluetoothctl; then
        v=$(timeout 2 bluetoothctl info "$mac" 2>/dev/null \
            | awk -F'[()]' '/Battery Percentage/{print $2; exit}' || true)
        if [ -n "$v" ]; then
            printf '%s\n' "$v"
            return 0
        fi
    fi
    have busctl || return 0
    path=$(timeout 2 busctl --system tree org.bluez 2>/dev/null \
        | tr -d ' │├└─' \
        | awk -v m="dev_${mac//:/_}" '$0 ~ m"$" {print; exit}' || true)
    [ -n "$path" ] || return 0
    v=$(timeout 2 busctl --system get-property org.bluez "$path" \
        org.bluez.Battery1 Percentage 2>/dev/null | awk '{print $2; exit}' || true)
    [ -n "$v" ] && printf '%s\n' "$v"
    return 0
}

wait_for_card() {
    local i=0
    while [ "$i" -lt 20 ]; do
        if timeout 1 pactl list cards short 2>/dev/null | grep -q 'bluez_card'; then
            return 0
        fi
        sleep 0.5
        i=$((i+1))
    done
    return 1
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
machine_status() {
    have pactl || { echo "error"; return 0; }

    local card
    card=$(find_card 2>/dev/null) || card=""
    if [ -z "$card" ]; then
        # Card not in pactl. Check if headset is connected in bluetoothctl:
        local mac conn
        mac=$(find_mac 2>/dev/null) || mac=""
        if [ -n "$mac" ] && have bluetoothctl; then
            conn=$(timeout 2 bluetoothctl info "$mac" 2>/dev/null | awk '/Connected:/{print $2}' || true)
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
    ' || true)

    case "$prof" in
        headset-head-unit*) echo "hfp"  ;;
        a2dp-sink*)         echo "a2dp" ;;
        off|"")             echo "off"  ;;
        *)                  echo "error";;
    esac
}

profile_label() {
    case "$1" in
        headset-head-unit*) echo "HFP call profile, mic + speaker" ;;
        a2dp-sink*)         echo "A2DP music profile, no mic" ;;
        off|"")             echo "standby" ;;
        *)                  echo "$1" ;;
    esac
}

print_info_json() {
    local state card prof mac name codec mic battery conn wp
    state=$(machine_status)
    card=$(find_card 2>/dev/null) || card=""
    prof=$(current_profile 2>/dev/null) || prof=""
    mac=$(find_mac 2>/dev/null) || mac=""
    name=$(device_name)
    codec=$(active_codec)
    mic=$(mic_source)
    conn=$(device_connected)
    battery=$(battery_level "$mac")
    case "$battery" in
        ''|*[!0-9]*) battery="" ;;
    esac
    if [ -f "$WP_CONF" ]; then wp=true; else wp=false; fi

    [ -n "$mac" ] || mac=""

    printf '{"state":"%s","profile":%s,"codec":%s,"device":%s,"mac":%s,' \
        "$(json_str "$state")" \
        "$([ -n "$prof" ]   && printf '"%s"' "$(json_str "$prof")"   || printf 'null')" \
        "$([ -n "$codec" ]  && printf '"%s"' "$(json_str "$codec")"  || printf 'null')" \
        "$([ -n "$name" ]   && printf '"%s"' "$(json_str "$name")"   || printf 'null')" \
        "$([ -n "$mac" ]    && printf '"%s"' "$(json_str "$mac")"    || printf 'null')"
    printf '"mic":%s,"connected":%s,"wp_config":%s,"battery":%s}\n' \
        "$([ -n "$mic" ] && printf 'true' || printf 'false')" \
        "$([ "$conn" = "yes" ] && printf 'true' || printf 'false')" \
        "$wp" \
        "$([ -n "$battery" ] && printf '%s' "$battery" || printf 'null')"
}

print_info_human() {
    local state card prof mac name codec mic
    state=$(machine_status)
    card=$(find_card 2>/dev/null) || card=""
    prof=$(current_profile 2>/dev/null) || prof=""
    mac=$(find_mac 2>/dev/null) || mac=""
    name=$(device_name)
    codec=$(active_codec)
    mic=$(mic_source)

    if [ -n "$name" ]; then
        if [ -n "$mac" ]; then
            echo "Device:  $name ($mac)"
        else
            echo "Device:  $name"
        fi
    fi
    if [ "$state" = "none" ]; then
        echo "State:   none (headset not connected)"
    elif [ "$state" = "error" ]; then
        echo "State:   error (could not read the audio profile)"
    else
        echo "State:   $state ($(profile_label "$prof"))"
    fi
    [ -n "$prof" ]  && echo "Profile: $prof"
    [ -n "$codec" ] && echo "Codec:   $codec"
    if [ -n "$mic" ]; then
        echo "Mic:     available ($mic)"
    else
        echo "Mic:     not available in this profile"
    fi
    if [ -f "$WP_CONF" ]; then
        echo "Config:  xm WirePlumber drop-in installed"
    else
        echo "Config:  WirePlumber defaults (auto-switching on)"
    fi
    local battery; battery=$(battery_level "$mac")
    [ -n "$battery" ] && echo "Battery: ${battery}%"
    return 0
}

# ------------------------------------------------------------------------------
# Microphone self-test
#   human: prints progress + VERDICT line (unchanged behaviour)
#   --json: stdout is ONLY a JSON object, progress goes to stderr
# ------------------------------------------------------------------------------
run_mic_test() {
    local mode="${1:-human}" live_file="${2:-}"
    require pactl parec python3

    local prof src
    prof=$(current_profile 2>/dev/null) || prof=""
    src=$(mic_source)

    if [ -z "$src" ]; then
        if [ "$mode" = "json" ]; then
            printf '{"ok":false,"error":"no-mic-source","verdict":"error","label":"NO MIC","levels":[]}\n'
        else
            echo "No headset mic source found; run '$APP_NAME call' first." >&2
        fi
        return 1
    fi

    if [ "$mode" = "json" ]; then
        echo "Recording 5s from $src ..." >&2
    else
        case "$prof" in
            headset-head-unit*) : ;;
            *) echo "NOTE: not in a mic-capable profile ($prof). Run '$APP_NAME call' first." ;;
        esac
        echo "Recording 5s from $src - TALK NOW (say a few sentences)..."
    fi

    python3 - "$mode" "$live_file" "$src" <<'PY'
import array
import json
import math
import os
import select
import subprocess
import sys
import time

mode = sys.argv[1]
live_path = sys.argv[2]
source = sys.argv[3]

sample_rate = 48000
bar_count = 50
chunk_samples = sample_rate // 10          # 100 ms per live level
chunk_bytes = chunk_samples * 2            # s16le

# Read parec directly instead of recording to a file first, so each 100 ms
# chunk can be published to the live sidecar while the five seconds are still
# running. One process owns the microphone; the widget only polls the file.
# A low server-side latency is what makes parec deliver 100 ms chunks while
# the test is running. With parec's default buffer the whole recording arrives
# in a burst near the end, which looks like a frozen waveform.
proc = subprocess.Popen(
    ["parec", "--rate=48000", "--channels=1", "--format=s16le",
     "--latency-msec=50", "-d", source],
    stdout=subprocess.PIPE,
    stderr=subprocess.DEVNULL,
    bufsize=0,
)

live = None
if live_path:
    try:
        live = open(live_path, "w", buffering=1, encoding="utf-8")
    except OSError:
        # A writable sidecar is a UI convenience, never a reason to fail a test.
        live = None

levels = []
peak = 0
samples = 0
pending = b""
deadline = time.monotonic() + 6.0   # five seconds recorded, one second slack

try:
    fd = proc.stdout.fileno()
    while len(levels) < bar_count and time.monotonic() < deadline:
        remaining = deadline - time.monotonic()
        ready, _, _ = select.select([fd], [], [], min(0.25, remaining))
        if not ready:
            continue

        block = os.read(fd, chunk_bytes - len(pending))
        if not block:
            break
        pending += block

        while len(pending) >= chunk_bytes and len(levels) < bar_count:
            raw, pending = pending[:chunk_bytes], pending[chunk_bytes:]
            audio = array.array("h")
            audio.frombytes(raw)
            p = max((abs(x) for x in audio), default=0)
            peak = max(peak, p)
            samples += len(audio)

            if p > 0:
                db = 20 * math.log10(p / 32768.0)
                level = max(0.0, min(1.0, (db + 60.0) / 60.0))
            else:
                level = 0.0
            levels.append(round(level, 3))
            if live is not None:
                live.write(f"{level:.3f}\n")
finally:
    if live is not None:
        live.close()
    if proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(timeout=1)
        except subprocess.TimeoutExpired:
            proc.kill()

# The final JSON contract is always 50 bars, even if the stream stalled early.
while len(levels) < bar_count:
    levels.append(0.0)

duration = round(samples / float(sample_rate), 2)
dbfs = round(20 * math.log10(peak / 32768.0), 1) if peak > 0 else -96.0

if peak > 800:
    verdict, label = "live", "LIVE"
elif peak > 150:
    verdict, label = "quiet", "QUIET"
else:
    verdict, label = "silent", "SILENT"

if mode == "json":
    print(json.dumps({
        "ok": True,
        "verdict": verdict,
        "label": label,
        "peak": peak,
        "peak_dbfs": dbfs,
        "duration": duration,
        "levels": levels,
    }))
else:
    print(f"samples={samples}  peak={peak}/32767  ({dbfs:.1f} dBFS)")
    if verdict == "live":
        print("VERDICT: LIVE - microphone is working")
    elif verdict == "quiet":
        print("VERDICT: QUIET - barely hearing you; move closer / raise headset mic volume")
    else:
        print("VERDICT: SILENT - run 'xm reset' then 'xm test' again")
PY
}

# ------------------------------------------------------------------------------
# Reconnect / link recovery
# ------------------------------------------------------------------------------
reconnect() {
    require bluetoothctl pactl

    local mac
    mac=$(find_mac)
    if [ -z "$mac" ]; then
        echo "Could not determine headset MAC; skipping reconnect." >&2
        return 1
    fi

    local attempt conn
    for attempt in 1 2 3; do
        echo "Resetting Bluetooth link on $mac (attempt $attempt/3) ..."
        timeout 6  bluetoothctl disconnect "$mac" >/dev/null 2>&1 || true
        sleep 1
        timeout 12 bluetoothctl connect    "$mac" >/dev/null 2>&1 || true

        if wait_for_card; then
            conn=$(timeout 2 bluetoothctl info "$mac" 2>/dev/null \
                | awk '/Connected:/{print $2; exit}' || true)
            # The card only exists while the link is up. An empty bluetoothctl
            # answer is not a failure: trust the card rather than reconnect a
            # second and third time for a status string we could not read.
            if [ "$conn" != "no" ]; then
                echo "Reconnected."
                return 0
            fi
        fi
        sleep 2
    done

    echo "Could not reconnect the headset after 3 attempts." >&2
    echo "Check that it is powered on, in range, and not connected to another device." >&2
    return 1
}

profile_available() {
    local card prof; card=$(find_card 2>/dev/null) || return 1; prof="$1"
    timeout 2 pactl list cards 2>/dev/null | awk -v c="$card" -v p="$prof" '
        $0 ~ "Name: "c {f=1}
        f && /^[ \t]*Profiles:/ {inp=1; next}
        f && /Active Profile:/ {inp=0}
        f && inp && $0 ~ "^[ \t]*"p":" {found=1}
        END {exit !found}
    '
}

set_profile() {
    local card prof; card=$(find_card) || return 1; prof="$1"

    # Right after a reconnect the card can appear before all its profiles do.
    # Wait briefly instead of failing the first switch after a Fix.
    local i=0
    while [ "$i" -lt 16 ] && ! profile_available "$prof"; do
        sleep 0.5
        i=$((i+1))
    done

    echo "Switching '$card' -> $prof ..."
    timeout 5 pactl set-card-profile "$card" "$prof" || {
        echo "Failed to set profile '$prof'." >&2
        echo "Available profiles on this card:" >&2
        list_card_profiles >&2
        return 1
    }

    # pactl normally applies the profile synchronously, but give WirePlumber a
    # short bounded window instead of sleeping for a full second. Polling also
    # covers systems where the active profile appears a little later.
    local active="" i=0
    while [ "$i" -lt 20 ]; do
        active=$(current_profile 2>/dev/null) || active=""
        [ "$active" = "$prof" ] && break
        sleep 0.05
        i=$((i+1))
    done
    if [ "$active" != "$prof" ]; then
        active=$(current_profile 2>/dev/null) || active=""
    fi

    # HFP also needs its SCO source. Wait only when it is not already there;
    # on a healthy link this returns immediately.
    case "$prof" in
        headset-head-unit*) wait_for_mic_source 20 0.05 || true ;;
    esac

    echo "Active profile now: ${active:-unknown}"
}

# ------------------------------------------------------------------------------
# Doctor - one screen that answers "why is my mic not working?"
# ------------------------------------------------------------------------------
run_doctor() {
    local fails=0 warns=0
    pass() { printf '  OK    %s\n' "$*"; }
    warn() { printf '  WARN  %s\n' "$*"; warns=$((warns+1)); }
    fail() { printf '  FAIL  %s\n' "$*"; fails=$((fails+1)); }

    echo "xm doctor - Bluetooth headset audio check"
    echo

    echo "Stack"
    for c in pactl bluetoothctl parec python3; do
        if have "$c"; then
            pass "$c found"
        else
            fail "$c missing"
        fi
    done
    if pactl info >/dev/null 2>&1; then
        pass "PulseAudio/PipeWire server reachable"
    else
        fail "cannot reach the PipeWire/PulseAudio server"
    fi
    if systemctl --user is-active --quiet wireplumber 2>/dev/null; then
        pass "WirePlumber service is running"
    elif pgrep -x wireplumber >/dev/null 2>&1; then
        pass "WirePlumber process is running"
    else
        warn "WirePlumber does not look active"
    fi
    if systemctl is-active --quiet bluetooth 2>/dev/null; then
        pass "Bluetooth service is running"
    else
        warn "Bluetooth service does not look active (could not check)"
    fi

    echo
    echo "Headset"
    local mac name card prof codec src conn
    mac=$(find_mac 2>/dev/null) || mac=""
    name=$(device_name)
    card=$(find_card 2>/dev/null) || card=""
    prof=$(current_profile 2>/dev/null) || prof=""
    codec=$(active_codec)
    src=$(mic_source)
    conn=$(device_connected)

    if [ -n "$name" ]; then
        pass "headset: $name${mac:+ ($mac)}"
    else
        fail "no Bluetooth headset detected"
    fi
    if [ "$conn" = "yes" ]; then
        pass "Bluetooth link connected"
    elif [ -n "$mac" ]; then
        warn "headset is paired but not connected"
    fi
    if [ -n "$card" ]; then
        pass "audio card present: $card"
    else
        fail "no bluez audio card in PipeWire"
    fi
    if [ -n "$prof" ]; then
        pass "active profile: $prof${codec:+ (codec $codec)}"
        case "$prof" in
            headset-head-unit*) pass "mic-capable profile is active" ;;
            a2dp-sink*)         warn "music profile active - no microphone (run: $APP_NAME call)" ;;
            *)                  warn "profile '$prof' is not a known call/music profile" ;;
        esac
    fi
    if [ -n "$src" ]; then
        pass "headset microphone source: $src"
    else
        warn "no headset microphone source (normal in A2DP / between calls)"
    fi

    echo
    echo "xm configuration"
    if [ -f "$WP_CONF" ]; then
        pass "WirePlumber drop-in installed"
    else
        warn "WirePlumber drop-in missing - automatic profile switching is on"
    fi
    if [ -n "$prof" ] && [ -n "$card" ]; then
        pass "profiles offered by the card:"
        timeout 2 pactl list cards 2>/dev/null | awk -v c="$card" '
            $0 ~ "Name: "c {f=1}
            f && /^[ \t]+[a-z0-9-]+: / && !/Active Profile/ {sub(/^[ \t]+/,""); sub(/:.*/,""); print "          " $0}
        ' | head -8
    fi

    echo
    if [ "$fails" -gt 0 ]; then
        echo "Result: $fails problem(s), $warns warning(s)."
        return 1
    elif [ "$warns" -gt 0 ]; then
        echo "Result: no hard failures, $warns warning(s)."
        return 0
    fi
    echo "Result: everything looks healthy."
    return 0
}

# ------------------------------------------------------------------------------
# Commands
# ------------------------------------------------------------------------------
usage() {
    cat <<EOF
$APP_NAME - Bluetooth XM headset meeting helper (Sony WH-1000XM3/XM4/XM5, WF-1000XM earbuds & similar)

Usage: $APP_NAME <command> [--json]

  call      Switch to HFP/mSBC   -> microphone + speaker BOTH work (use before a meeting)
  music     Switch to A2DP/LDAC  -> best-quality output only, no mic (use after a meeting)
  status    Show the current Bluetooth audio profile
           (add --machine to print one bare token: a2dp | hfp | off | none | error,
            used by the KDE Plasma widget)
  info      Show device, codec, mic and config details (add --json for machines)
  test      Record 5s from the mic and report LIVE / QUIET / SILENT (talk during it)
           (add --json for the verdict and a 50-bar level waveform)
  reset     Reconnect the headset to clear a dead/silent mic link
  reconnect Alias for reset
  fix       reconnect + switch to 'call' profile in one shot (pre-meeting one-liner)
  doctor    Diagnose PipeWire, WirePlumber, BlueZ, profile and mic state
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
    machine_status
    exit 0
fi

case "$cmd" in
    call)
        require pactl bluetoothctl
        set_profile headset-head-unit
        echo "In Teams/Zoom set Speaker = your headset and Microphone = your headset."
        ;;
    music)
        require pactl bluetoothctl
        set_profile a2dp-sink
        ;;
    status)
        require pactl bluetoothctl
        card=$(find_card 2>/dev/null) || card=""
        if [ -z "$card" ]; then
            echo "State:   none - no headset connected"
            name=$(device_name)
            [ -n "$name" ] && echo "Device:  $name (paired, not connected)"
            exit 0
        fi
        echo "Profile: $(current_profile)"
        echo "Device:  $(device_name)"
        codec=$(active_codec)
        [ -n "$codec" ] && echo "Codec:   $codec"
        ;;

    info)
        if [ "${2:-}" = "--json" ]; then
            print_info_json
        else
            print_info_human
        fi
        ;;
    test)
        # Internal options for the applet: --live-file PATH receives one real
        # 100 ms level per line while the recording is still in progress.
        test_mode="human"
        test_live_file=""
        shift
        while [ "$#" -gt 0 ]; do
            case "$1" in
                --json) test_mode="json" ;;
                --live-file=*) test_live_file="${1#*=}" ;;
                --live-file)
                    shift
                    [ "$#" -gt 0 ] || {
                        echo "--live-file needs a path" >&2
                        exit 2
                    }
                    test_live_file="$1"
                    ;;
                *)
                    echo "Unknown option for '$APP_NAME test': $1" >&2
                    exit 2
                    ;;
            esac
            shift
        done
        run_mic_test "$test_mode" "$test_live_file"
        ;;
    reset|reconnect)
        reconnect
        echo "Profile now: $(current_profile)"
        ;;
    fix)
        reconnect
        set_profile headset-head-unit
        # Give PipeWire a moment to publish the SCO source after the switch.
        if wait_for_mic_source; then
            echo "Ready for meeting (microphone + speaker on the headset)."
        else
            echo "Switched to Call, but the mic source is not visible yet." >&2
            echo "If people cannot hear you, run '$APP_NAME doctor'." >&2
        fi
        ;;
    doctor)
        run_doctor
        ;;
    defaults-reset)
        if [ -f "$WP_CONF" ]; then
            rm -f "$WP_CONF"
            echo "Removed ${WP_CONF}"
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
