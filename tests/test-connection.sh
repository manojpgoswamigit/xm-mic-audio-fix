#!/usr/bin/env bash
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/bin"
cat > "$tmp/bin/pactl" <<'SH'
#!/usr/bin/env bash
exit 0
SH
cat > "$tmp/bin/sleep" <<'SH'
#!/usr/bin/env bash
exit 0
SH
cat > "$tmp/bin/bluetoothctl" <<'SH'
#!/usr/bin/env bash
case "$1" in
 devices)
    [ "${NO_DEVICE:-0}" = 0 ] || exit 0
    if [ "${2:-}" != Connected ] || [ "$(cat "$BT_STATE")" = yes ]; then
        echo 'Device AA:BB:CC:DD:EE:FF Test Headset'
    fi ;;
 info)
    echo 'Name: Test Headset'
    echo 'Icon: audio-headset'
    echo "Connected: $(cat "$BT_STATE")" ;;
 connect|disconnect)
    [ "$2" = AA:BB:CC:DD:EE:FF ] || exit 1
    echo "$1" >> "$BT_LOG"
    [ "${BT_FAIL:-0}" = 0 ] || exit 1
    [ "${BT_STUCK:-0}" = 0 ] || exit 0
    if [ "$1" = connect ]; then echo yes; else echo no; fi > "$BT_STATE" ;;
esac
SH
chmod +x "$tmp/bin/"*
export PATH="$tmp/bin:$PATH" BT_STATE="$tmp/state" BT_LOG="$tmp/log"
echo no > "$BT_STATE"
bash "$repo/xm.sh" connect
[ "$(cat "$BT_STATE")" = yes ]
bash "$repo/xm.sh" connect
[ "$(wc -l < "$BT_LOG")" = 1 ] # Already connected must not reset the link.
bash "$repo/xm.sh" disconnect
[ "$(cat "$BT_STATE")" = no ]
bash "$repo/xm.sh" disconnect
[ "$(wc -l < "$BT_LOG")" = 2 ]
bash "$repo/xm.sh" toggle
[ "$(cat "$BT_STATE")" = yes ]
bash "$repo/xm.sh" toggle
[ "$(cat "$BT_STATE")" = no ]
if BT_FAIL=1 bash "$repo/xm.sh" connect; then echo 'FAIL: command failure accepted'; exit 1; fi
if BT_STUCK=1 bash "$repo/xm.sh" connect; then echo 'FAIL: unconfirmed connection accepted'; exit 1; fi
if NO_DEVICE=1 bash "$repo/xm.sh" connect; then echo 'FAIL: missing headset accepted'; exit 1; fi
echo 'PASS: connection commands, idempotence, toggle, and failures'
