#!/usr/bin/env bash
# =============================================================================
#  Profile switch latency
# =============================================================================
#  `xm call` / `xm music` must return as soon as the profile is actually
#  active. An unconditional sleep after pactl turns a ~30 ms switch into a
#  one-second wait, which is exactly what the widget's Call/Music buttons feel.
#
#  Also covers cards that only expose the mandatory CVSD/SBC profiles, which
#  is what older headsets and systems with mSBC disabled provide.
#
#  Uses fake pactl/bluetoothctl binaries, so it is deterministic and does not
#  need a headset.
# =============================================================================

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/xm-switch-test.XXXXXX")
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/bin"
state="$tmp/profile"
echo "a2dp-sink" > "$state"

cat > "$tmp/bin/pactl" <<'SH'
#!/usr/bin/env bash
state_file=${FAKE_PACTL_STATE:?}
profiles=${FAKE_PACTL_PROFILES:-full}
active=$(cat "$state_file")

case "${1:-}" in
    list)
        case "${2:-}" in
            cards)
                if [ "${3:-}" = "short" ]; then
                    printf '1\tbluez_card.80_99_E7_36_CB_CA\tbluez5\tmodule-bluez5-device\n'
                elif [ "$profiles" = "legacy" ]; then
                    cat <<EOF
Card #1
	Name: bluez_card.80_99_E7_36_CB_CA
	Profiles:
		headset-head-unit-cvsd: HFP/CVSD
		a2dp-sink-sbc: A2DP/SBC
	Active Profile: $active
EOF
                else
                    cat <<EOF
Card #1
	Name: bluez_card.80_99_E7_36_CB_CA
	Profiles:
		headset-head-unit: HFP/mSBC
		headset-head-unit-cvsd: HFP/CVSD
		a2dp-sink: A2DP/LDAC
		a2dp-sink-sbc: A2DP/SBC
	Active Profile: $active
EOF
                fi
                ;;
            sources)
                case "$active" in
                    headset-head-unit*)
                        printf '1\tbluez_input.80:99:E7:36:CB:CA\tPipeWire\trecord\tRUNNING\n'
                        ;;
                esac
                ;;
        esac
        ;;
    set-card-profile)
        printf '%s\n' "${3:?missing profile}" > "$state_file"
        ;;
esac
SH

cat > "$tmp/bin/bluetoothctl" <<'SH'
#!/usr/bin/env bash
exit 0
SH

chmod +x "$tmp/bin/pactl" "$tmp/bin/bluetoothctl"

profiles=full
run_switch() {
    local target=$1 start end
    start=$(date +%s%N)
    PATH="$tmp/bin:$PATH" FAKE_PACTL_STATE="$state" \
        FAKE_PACTL_PROFILES="$profiles" \
        "$repo_root/xm.sh" "$target" >"$tmp/$target.out" 2>"$tmp/$target.err"
    end=$(date +%s%N)
    printf '%s\n' $(( (end - start) / 1000000 ))
}

call_ms=$(run_switch call)
[ "$(cat "$state")" = "headset-head-unit" ] || {
    echo "FAIL: call did not activate HFP" >&2
    exit 1
}

music_ms=$(run_switch music)
[ "$(cat "$state")" = "a2dp-sink" ] || {
    echo "FAIL: music did not activate A2DP" >&2
    exit 1
}

# A card with only the mandatory CVSD/SBC profiles must still switch. Older
# headsets (and cards with mSBC disabled) expose these names instead.
profiles=legacy
echo "a2dp-sink-sbc" > "$state"
legacy_call_ms=$(run_switch call)
[ "$(cat "$state")" = "headset-head-unit-cvsd" ] || {
    echo "FAIL: call did not fall back to CVSD" >&2
    exit 1
}

legacy_music_ms=$(run_switch music)
[ "$(cat "$state")" = "a2dp-sink-sbc" ] || {
    echo "FAIL: music did not fall back to SBC" >&2
    exit 1
}

# The fake pactl is instant, so anything near a second is an artificial wait.
limit_ms=800
if [ "$call_ms" -gt "$limit_ms" ] || [ "$music_ms" -gt "$limit_ms" ] \
    || [ "$legacy_call_ms" -gt "$limit_ms" ] || [ "$legacy_music_ms" -gt "$limit_ms" ]; then
    echo "FAIL: profile switches too slow (call=${call_ms}ms music=${music_ms}ms fallback-call=${legacy_call_ms}ms fallback-music=${legacy_music_ms}ms, limit=${limit_ms}ms)" >&2
    exit 1
fi

echo "PASS: call=${call_ms}ms music=${music_ms}ms fallback-call=${legacy_call_ms}ms fallback-music=${legacy_music_ms}ms"
