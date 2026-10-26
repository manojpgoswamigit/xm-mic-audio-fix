#!/usr/bin/env bash
# =============================================================================
#  Plasma widget icon contract
# =============================================================================
#  The About and Close controls used to be font glyphs, and the footer author
#  link used a globe. Keep the widget on native Breeze symbolic icons, and keep
#  the disconnected state visually distinct from an error.
# =============================================================================

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

python3 - "$repo_root" <<'PY'
import pathlib
import re
import sys

ui_dir = pathlib.Path(sys.argv[1]) / "plasmoid/contents/ui"
popup_path = ui_dir / "HeadsetPopup.qml"
mic_path = ui_dir / "MicTestPanel.qml"
for path in (popup_path, mic_path):
    if not path.is_file():
        raise SystemExit(f"FAIL: missing {path}")

popup = popup_path.read_text(encoding="utf-8")
mic_panel = mic_path.read_text(encoding="utf-8")
errors = []

def block(anchor, span=900):
    start = popup.find(anchor)
    if start < 0:
        return ""
    return popup[start:start + span]

if 'text: "ⓘ"' in popup:
    errors.append("About still uses the ⓘ font glyph")
if 'text: "✕"' in popup:
    errors.append("Close still uses the ✕ font glyph")

about = block('objectName: "aboutButton"')
if 'icon.name: "help-about-symbolic"' not in about:
    errors.append("aboutButton must use help-about-symbolic")

close = block('Accessible.name: "Close"', 500)
if 'icon.name: "window-close-symbolic"' not in close:
    errors.append("overlay Close must use window-close-symbolic")

author = block('id: authorButton', 900)
if 'icon.name: "user-identity-symbolic"' not in author:
    errors.append("footer author link must use user-identity-symbolic")

if not re.search(
    r'source:\s*root\.state\s*===\s*"none"\s*\?\s*"network-bluetooth-inactive-symbolic"',
    popup,
    re.DOTALL,
):
    errors.append("disconnected state must use network-bluetooth-inactive-symbolic")

for icon in (
    '"view-refresh-symbolic"',
    '"tools-symbolic"',
    '"edit-undo-symbolic"',
    '"audio-headset-symbolic"',
    '"audio-speakers-symbolic"',
):
    if icon not in popup:
        errors.append(f"expected existing icon {icon} disappeared")

if '"audio-input-microphone-symbolic"' not in mic_panel:
    errors.append('expected existing icon "audio-input-microphone-symbolic" disappeared')

if errors:
    for error in errors:
        print(f"FAIL: {error}", file=sys.stderr)
    raise SystemExit(1)

print("PASS: widget icon map is consistent")
PY
