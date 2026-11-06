#!/usr/bin/env bash
# =============================================================================
#  Headset volume: `xm volume`, `xm mic-volume` and the info --json fields
# =============================================================================
#  The widget's sliders run these commands, so they must:
#    * act on the headset's own nodes, never on another Bluetooth device or
#      the system default
#    * cap levels to 0-100 and reject anything that is not a level
#    * refuse the mic in Music (there is no mic node in A2DP)
#    * report levels in info --json as ints / bools, or null when absent
#
#  Uses a stateful fake pactl: no headset required.
# =============================================================================

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/xm-volume-test.XXXXXX")
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/bin" "$tmp/state"
export FAKE_STATE="$tmp/state"

cat > "$tmp/bin/pactl" <<'SH'
#!/usr/bin/env bash
st=${FAKE_STATE:?}
card=$(cat "$st/card")
active=$(cat "$st/profile" 2>/dev/null || echo a2dp-sink)

# node -> file key (names contain ':' in the colon-form mic)
key() { printf '%s' "$1" | tr ':/' '__'; }
get_vol()  { cat "$st/vol.$(key "$1")"  2>/dev/null || echo 54; }
get_mute() { cat "$st/mute.$(key "$1")" 2>/dev/null || echo no; }
known() {
    # Only nodes that are actually listed may be addressed.
    "$0" list "$2s" short | awk '{print $2}' | grep -qxF "$1"
}

case "${1:-}" in
    info)
        echo "Server Name: PulseAudio (on PipeWire 1.2.0)"
        ;;
    list)
        case "${2:-}" in
            cards)
                [ "$card" = yes ] || exit 0
                if [ "${3:-}" = "short" ]; then
                    printf '1\tbluez_card.AA_BB_CC_DD_EE_FF\tbluez5\n'
                else
                    cat <<EOF
Card #1
	Name: bluez_card.AA_BB_CC_DD_EE_FF
	Properties:
		api.bluez5.address = "AA:BB:CC:DD:EE:FF"
	Profiles:
		headset-head-unit: HFP/mSBC (codec mSBC)
		a2dp-sink: A2DP/LDAC (codec LDAC)
	Active Profile: $active
EOF
                fi
                ;;
            sinks)
                # A second Bluetooth speaker is listed FIRST on purpose.
                printf '40\tbluez_output.11_22_33_44_55_66.1\tPipeWire\n'
                printf '41\talsa_output.pci.analog-stereo\tPipeWire\n'
                # Standby (profile off) has no headset sink at all.
                if [ "$card" = yes ] && [ "$active" != off ]; then
                    printf '42\tbluez_output.AA_BB_CC_DD_EE_FF.1\tPipeWire\n'
                fi
                ;;
            sources)
                printf '50\tbluez_output.11_22_33_44_55_66.1.monitor\tPipeWire\n'
                # The other Bluetooth device has a live mic of its own.
                printf '54\tbluez_input.11_22_33_44_55_66.0\tPipeWire\n'
                printf '51\talsa_input.usb-mic\tPipeWire\n'
                if [ "$card" = yes ]; then
                    printf '52\tbluez_output.AA_BB_CC_DD_EE_FF.1.monitor\tPipeWire\n'
                    case "$active" in
                        # Older stacks: colon-form node name.
                        headset-head-unit*) printf '53\tbluez_input.AA:BB:CC:DD:EE:FF\tPipeWire\n' ;;
                    esac
                fi
                ;;
        esac
        ;;
    get-sink-volume|get-source-volume)
        kind=${1#get-}; kind=${kind%-volume}
        known "$2" "$kind" || { echo "Failure: No such entity" >&2; exit 1; }
        v=$(get_vol "$2")
        echo "Volume: front-left: 1 /  ${v}% / 0 dB,   front-right: 1 /  ${v}% / 0 dB"
        ;;
    get-sink-mute|get-source-mute)
        kind=${1#get-}; kind=${kind%-mute}
        known "$2" "$kind" || { echo "Failure: No such entity" >&2; exit 1; }
        echo "Mute: $(get_mute "$2")"
        ;;
    set-sink-volume|set-source-volume)
        kind=${1#set-}; kind=${kind%-volume}
        known "$2" "$kind" || { echo "Failure: No such entity" >&2; exit 1; }
        printf '%s\n' "${3%\%}" > "$st/vol.$(key "$2")"
        echo "$1 $2 $3" >> "$st/log"
        ;;
    set-sink-mute|set-source-mute)
        kind=${1#set-}; kind=${kind%-mute}
        known "$2" "$kind" || { echo "Failure: No such entity" >&2; exit 1; }
        case "$3" in
            1) m=yes ;;
            0) m=no ;;
            toggle) [ "$(get_mute "$2")" = yes ] && m=no || m=yes ;;
        esac
        printf '%s\n' "$m" > "$st/mute.$(key "$2")"
        echo "$1 $2 $3" >> "$st/log"
        ;;
esac
exit 0
SH

cat > "$tmp/bin/bluetoothctl" <<'SH'
#!/usr/bin/env bash
if [ "${1:-}" = info ]; then
    echo "$2" >> "$FAKE_STATE/bluez-info"
    printf '  Name: Fixture headset\n  Connected: yes\n  Battery Percentage: 0x50 (80)\n'
fi
exit 0
SH
cat > "$tmp/bin/busctl" <<'SH'
#!/usr/bin/env bash
exit 0
SH
chmod +x "$tmp/bin/pactl" "$tmp/bin/bluetoothctl" "$tmp/bin/busctl"

fail() { echo "FAIL: $*" >&2; exit 1; }
xm() { PATH="$tmp/bin:$PATH" "$repo_root/xm.sh" "$@"; }

HS_SINK=bluez_output.AA_BB_CC_DD_EE_FF.1
HS_SRC=bluez_input.AA_BB_CC_DD_EE_FF
OTHER_SINK=bluez_output.11_22_33_44_55_66.1
OTHER_SRC=bluez_input.11_22_33_44_55_66.0
key() { printf '%s' "$1" | tr ':/' '__'; }
vol_of()  { cat "$FAKE_STATE/vol.$(key "$1")" 2>/dev/null || echo 54; }
mute_of() { cat "$FAKE_STATE/mute.$(key "$1")" 2>/dev/null || echo no; }

# expect_rc <rc> <cmd...>: run, keep stdout/stderr in $out/$err
expect_rc() {
    local want=$1 rc=0; shift
    xm "$@" >"$tmp/out" 2>"$tmp/err" || rc=$?
    out=$(cat "$tmp/out"); err=$(cat "$tmp/err")
    [ "$rc" -eq "$want" ] || fail "xm $* exited $rc, expected $want (stderr: $err)"
}

echo yes > "$FAKE_STATE/card"
echo a2dp-sink > "$FAKE_STATE/profile"

# ---- speaker: read, set, cap, nudge ------------------------------------
expect_rc 0 volume
[ "$out" = "Speaker: 54%" ] || fail "read: '$out'"

expect_rc 0 volume 60
[ "$(vol_of "$HS_SINK")" = 60 ] || fail "set 60 did not reach the headset sink"
[ ! -f "$FAKE_STATE/vol.$(key "$OTHER_SINK")" ] || fail "touched the other Bluetooth sink"
[ "$out" = "Speaker volume: 60%" ] || fail "set output: '$out'"

expect_rc 0 volume 150;  [ "$(vol_of "$HS_SINK")" = 100 ] || fail "150 not capped to 100"
expect_rc 0 volume +10;  [ "$(vol_of "$HS_SINK")" = 100 ] || fail "+10 went past 100"
expect_rc 0 volume -30;  [ "$(vol_of "$HS_SINK")" = 70 ]  || fail "-30 from 100 != 70"
expect_rc 0 volume -200; [ "$(vol_of "$HS_SINK")" = 0 ]   || fail "-200 not floored to 0"
expect_rc 0 volume 007;  [ "$(vol_of "$HS_SINK")" = 7 ]   || fail "007 not read as decimal 7"
expect_rc 0 volume 45%;  [ "$(vol_of "$HS_SINK")" = 45 ]  || fail "45% not accepted"

# ---- speaker: mute --------------------------------------------------------
expect_rc 0 volume mute;   [ "$(mute_of "$HS_SINK")" = yes ] || fail "mute"
expect_rc 0 volume
[ "$out" = "Speaker: 45% (muted)" ] || fail "muted read: '$out'"
expect_rc 0 volume unmute; [ "$(mute_of "$HS_SINK")" = no ]  || fail "unmute"
expect_rc 0 volume toggle; [ "$(mute_of "$HS_SINK")" = yes ] || fail "toggle on"
[ "$out" = "Speaker muted" ] || fail "toggle output: '$out'"
expect_rc 0 volume toggle; [ "$(mute_of "$HS_SINK")" = no ]  || fail "toggle off"

# ---- bad input never reaches pactl ----------------------------------------
before=$(wc -l < "$FAKE_STATE/log")
for bad in abc 1000 50x +x -- "+5 5"; do
    expect_rc 2 volume "$bad"
done
expect_rc 2 volume 1 2
[ "$(wc -l < "$FAKE_STATE/log")" = "$before" ] || fail "bad input changed the volume"

# ---- mic: refused in Music --------------------------------------------------
expect_rc 1 mic-volume
case "$err" in *"Call profile"*) ;; *) fail "mic in Music: '$err'" ;; esac
expect_rc 1 mic-volume 50
[ ! -f "$FAKE_STATE/vol.$(key "$OTHER_SRC")" ] || fail "Music: changed the other device's mic"

# ---- info --json in Music -------------------------------------------------
: > "$FAKE_STATE/bluez-info"
json=$(xm info --json)
[ "$(wc -l < "$FAKE_STATE/bluez-info")" -eq 1 ] || fail "info repeats the BlueZ device query"
python3 - "$json" <<'PY' || fail "info --json (music): $json"
import json, sys
o = json.loads(sys.argv[1])
# mic_volume must stay null although another device has a live mic.
assert o["speaker_volume"] == 45 and type(o["speaker_volume"]) is int, o
assert o["speaker_muted"] is False, o
assert (o["device"], o["connected"], o["battery"]) == ("Fixture headset", True, 80), o
assert o["mic_volume"] is None and o["mic_muted"] is None, o
PY

# ---- mic in Call (colon-form node name) -----------------------------------
echo headset-head-unit > "$FAKE_STATE/profile"
expect_rc 0 mic-volume
[ "$out" = "Mic: 54%" ] || fail "mic read: '$out'"
expect_rc 0 mic-volume 40
[ "$(vol_of "$HS_SRC")" = 40 ] || fail "mic set did not reach the headset source"
[ ! -f "$FAKE_STATE/vol.alsa_input.usb-mic" ] || fail "touched the default mic"
expect_rc 0 mic-volume mute
[ "$(mute_of "$HS_SRC")" = yes ] || fail "mic mute"

json=$(xm info --json)
python3 - "$json" <<'PY' || fail "info --json (call): $json"
import json, sys
o = json.loads(sys.argv[1])
assert o["mic_volume"] == 40 and o["mic_muted"] is True, o
assert o["speaker_volume"] == 45, o
PY

# ---- standby: no headset nodes, other device untouched -------------------
echo off > "$FAKE_STATE/profile"
rm -f "$FAKE_STATE/vol."* "$FAKE_STATE/mute."*
expect_rc 1 volume 50
expect_rc 1 volume mute
expect_rc 1 mic-volume 50
ls "$FAKE_STATE"/vol.* "$FAKE_STATE"/mute.* >/dev/null 2>&1 \
    && fail "standby: changed another device ($(ls "$FAKE_STATE" | grep -E '^(vol|mute)\.'))"
json=$(xm info --json)
python3 - "$json" <<'PY' || fail "info --json (standby): $json"
import json, sys
o = json.loads(sys.argv[1])
for k in ("speaker_volume", "speaker_muted", "mic_volume", "mic_muted"):
    assert o[k] is None, (k, o)
PY

# ---- no headset -------------------------------------------------------------
echo no > "$FAKE_STATE/card"
expect_rc 1 volume
case "$err" in *"connected"*) ;; *) fail "no headset: '$err'" ;; esac
expect_rc 1 volume 50
json=$(xm info --json)
python3 - "$json" <<'PY' || fail "info --json (none): $json"
import json, sys
o = json.loads(sys.argv[1])
for k in ("speaker_volume", "speaker_muted", "mic_volume", "mic_muted"):
    assert o[k] is None, (k, o)
PY

echo "PASS: speaker + mic levels, caps, mute, bad input, profile gating, other-device safety, info --json"
