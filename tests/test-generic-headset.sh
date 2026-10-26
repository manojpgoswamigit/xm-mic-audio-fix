#!/usr/bin/env bash
# =============================================================================
#  Generic Bluetooth headset detection
# =============================================================================
#  The profile switcher is model-agnostic: it drives the standard PipeWire
#  bluez_card profiles. The MAC lookup fallback must be model-agnostic too, so
#  a connected non-Sony headset is still recognised when the card is not in
#  pactl yet (for example during reconnect / standby).
#
#  Uses fake pactl/bluetoothctl binaries: no headset required.
# =============================================================================

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/xm-generic-test.XXXXXX")
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/bin"

cat > "$tmp/bin/pactl" <<'SH'
#!/usr/bin/env bash
# No bluez_card: exercise the BlueZ fallback path.
case "${1:-}" in
    list) exit 0 ;;
esac
exit 0
SH

cat > "$tmp/bin/busctl" <<'SH'
#!/usr/bin/env bash
# Keep Battery1 fallback deterministic in the test environment.
exit 0
SH

cat > "$tmp/bin/bluetoothctl" <<'SH'
#!/usr/bin/env bash
scenario=${FAKE_BT_SCENARIO:-connected}

case "${1:-}" in
    devices)
        if [ "${2:-}" = "Connected" ]; then
            case "$scenario" in
                connected)
                    printf '%s\n' \
                        'Device 11:22:33:44:55:66 MX Master 3S' \
                        'Device AA:BB:CC:DD:EE:FF QuietComfort Ultra'
                    ;;
                hid)
                    printf '%s\n' 'Device 11:22:33:44:55:66 MX Master 3S'
                    ;;
            esac
        else
            case "$scenario" in
                connected)
                    printf '%s\n' \
                        'Device 11:22:33:44:55:66 MX Master 3S' \
                        'Device AA:BB:CC:DD:EE:FF QuietComfort Ultra'
                    ;;
                paired)
                    printf '%s\n' 'Device AA:BB:CC:DD:EE:FF QuietComfort Ultra'
                    ;;
                hid)
                    printf '%s\n' 'Device 11:22:33:44:55:66 MX Master 3S'
                    ;;
            esac
        fi
        ;;
    info)
        case "${2:-}" in
            11:22:33:44:55:66)
                cat <<'EOF'
Device 11:22:33:44:55:66 (public)
	Name: MX Master 3S
	Icon: input-mouse
	Connected: yes
	UUID: Human Interface Device    (00001124-0000-1000-8000-00805f9b34fb)
EOF
                ;;
            AA:BB:CC:DD:EE:FF)
                if [ "$scenario" = "paired" ]; then
                    cat <<'EOF'
Device AA:BB:CC:DD:EE:FF (public)
	Name: QuietComfort Ultra
	Icon: audio-headset
	Connected: no
	UUID: Headset                   (00001108-0000-1000-8000-00805f9b34fb)
	UUID: Audio Sink                (0000110b-0000-1000-8000-00805f9b34fb)
	UUID: Handsfree                 (0000111e-0000-1000-8000-00805f9b34fb)
EOF
                else
                    cat <<'EOF'
Device AA:BB:CC:DD:EE:FF (public)
	Name: QuietComfort Ultra
	Icon: audio-headset
	Connected: yes
	UUID: Headset                   (00001108-0000-1000-8000-00805f9b34fb)
	UUID: Audio Sink                (0000110b-0000-1000-8000-00805f9b34fb)
	UUID: Handsfree                 (0000111e-0000-1000-8000-00805f9b34fb)
	Battery Percentage: 0x4b (75)
EOF
                fi
                ;;
        esac
        ;;
esac
exit 0
SH

chmod +x "$tmp/bin/pactl" "$tmp/bin/busctl" "$tmp/bin/bluetoothctl"
export PATH="$tmp/bin:$PATH"

scenario=connected
xm_run() {
    FAKE_BT_SCENARIO="$scenario" "$repo_root/xm.sh" "$@"
}

assert_json() {
    python3 - "$1" "$2" <<'PY'
import json
import sys

actual = json.loads(sys.argv[1])
expected = json.loads(sys.argv[2])
for key, value in expected.items():
    if actual.get(key) != value:
        raise SystemExit(
            f"FAIL: info.{key} = {actual.get(key)!r}, expected {value!r}\n{actual}"
        )
PY
}

machine=$(xm_run status --machine)
[ "$machine" = "off" ] || {
    echo "FAIL: connected non-Sony headset should report 'off'; got '$machine'" >&2
    exit 1
}
assert_json "$(xm_run info --json)" \
    '{"state":"off","device":"QuietComfort Ultra","mac":"AA:BB:CC:DD:EE:FF","battery":75,"connected":true}'

# A paired but disconnected audio device should still be named by `xm info`.
scenario=paired
machine=$(xm_run status --machine)
[ "$machine" = "none" ] || {
    echo "FAIL: disconnected headset should report 'none'; got '$machine'" >&2
    exit 1
}
assert_json "$(xm_run info --json)" \
    '{"state":"none","device":"QuietComfort Ultra","mac":"AA:BB:CC:DD:EE:FF","battery":null,"connected":false}'

# A connected HID device must not be mistaken for a headset.
scenario=hid
machine=$(xm_run status --machine)
[ "$machine" = "none" ] || {
    echo "FAIL: HID-only device should report 'none'; got '$machine'" >&2
    exit 1
}
assert_json "$(xm_run info --json)" \
    '{"state":"none","device":null,"mac":null,"battery":null,"connected":false}'

echo "PASS: non-Sony audio devices detected; HID devices ignored"
