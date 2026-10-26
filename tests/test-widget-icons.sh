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

github_path = ui_dir / "GitHubIcon.qml"
if not github_path.is_file():
    raise SystemExit(f"FAIL: missing {github_path}")
github = github_path.read_text(encoding="utf-8")
if "PathSvg" not in github:
    errors.append("GitHubIcon.qml must draw the mark with PathSvg")

repo = block('id: aboutRepoButton', 1600)
if "GitHubIcon" not in repo:
    errors.append("aboutRepoButton must draw GitHubIcon")
if "internet-web-browser-symbolic" in popup:
    errors.append("the About GitHub link must not use a browser icon")
if 'Accessible.name: "Open the xm GitHub repository"' not in repo:
    errors.append("aboutRepoButton must keep its accessible name")

main_path = ui_dir / "main.qml"
main = main_path.read_text(encoding="utf-8")

if "readonly property string compactIconSource" not in main:
    errors.append("main.qml must define compactIconSource")
if "source: root.compactIconSource" not in main:
    errors.append("compactRepresentation must use compactIconSource")
if "network-bluetooth-inactive-symbolic" not in main:
    errors.append("compact icon must switch to the inactive Bluetooth glyph")
if "dialog-warning-symbolic" not in main:
    errors.append("compact icon must switch to the warning glyph on error")

if "readonly property string headerIcon" not in popup:
    errors.append("HeadsetPopup must define headerIcon")
if "source: root.headerIcon" not in popup:
    errors.append("popup header must use headerIcon")

recovery = block('id: recoveryRow', 1800)
if "color: root.stateColor" not in recovery:
    errors.append("recovery card must use the state colour")
if "color: root.colorBusy" in recovery:
    errors.append("recovery card must not use the busy colour")

chip_path = ui_dir / "Chip.qml"
if not chip_path.is_file():
    raise SystemExit(f"FAIL: missing {chip_path}")
chip = chip_path.read_text(encoding="utf-8")
for token in ("property string text", "property string iconName",
              "property color tint", "property bool filled"):
    if token not in chip:
        errors.append(f"Chip.qml must define {token}")

if "readonly property string batteryIcon" not in popup:
    errors.append("HeadsetPopup must define batteryIcon")
if "iconName: root.batteryIcon" not in popup:
    errors.append("battery chip must use batteryIcon")
if "Chip {" not in popup:
    errors.append("header must use the shared Chip component")

if "readonly property string statusIcon" not in mic_panel:
    errors.append("MicTestPanel must define statusIcon")
for icon in ('"media-record-symbolic"', '"audio-volume-low-symbolic"',
             '"audio-volume-muted-symbolic"', '"dialog-error-symbolic"'):
    if icon not in mic_panel:
        errors.append(f"MicTestPanel must use {icon}")
if '"MIC INPUT"' not in mic_panel:
    errors.append('MicTestPanel must title the hero "MIC INPUT"')
if '"−"' not in mic_panel:
    errors.append("MicTestPanel must format negative peaks with a typographic minus")

if errors:
    for error in errors:
        print(f"FAIL: {error}", file=sys.stderr)
    raise SystemExit(1)

print("PASS: widget icon map is consistent")
PY
