# Widget Icon Consistency Pass Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the widget’s weak font-glyph and mismatched icons with native Breeze symbolic icons without changing layout or behaviour.

**Architecture:** Only `plasmoid/contents/ui/HeadsetPopup.qml` changes. The header About and overlay Close controls become normal icon-only Plasma tool buttons; the footer author link gets a person icon; the disconnected recovery header gets the inactive Bluetooth icon. A small shell contract test pins the icon map so future edits cannot quietly restore the glyphs.

**Tech Stack:** QML, Plasma 6, Kirigami, the Breeze icon theme, `qml6`, shell and Python 3.

**Spec:** `docs/superpowers/specs/2026-10-25-widget-icons-design.md`

## Global Constraints

- Use Breeze symbolic icons only; no new assets or dependencies.
- Do not change layout, colours, spacing, audio behaviour, or configuration.
- Keep the existing user-level, no-root, no-daemon design.
- Do not push.
- All existing tests must keep passing.

## Review Focus

- Every icon name must exist in the active Breeze theme, especially `network-bluetooth-inactive-symbolic`.
- Removing the custom `contentItem` from About/Close must not break focus, hover, tooltips, or accessibility names.
- ToolButton icon size and colour must match neighbouring icons in light and dark themes.
- The footer author link must keep the same GitHub URL and remain visually secondary.
- Disconnected and error states must remain visually distinct: inactive Bluetooth vs warning triangle.

---

### Task 1: Replace weak icons and pin the contract

**Files:**
- Create: `tests/test-widget-icons.sh`
- Modify: `plasmoid/contents/ui/HeadsetPopup.qml` (About button, overlay Close button, footer author link, recovery icon)
- Commit: `docs/superpowers/specs/2026-10-25-widget-icons-design.md` and this plan with the code change.

**Interfaces:**
- Consumes: existing `root.fgColor`, `root.state`, `Kirigami.Units.iconSizes`, and the existing GitHub URLs.
- Produces: no public API; visual-only QML changes.

- [ ] **Step 1: Write the failing icon contract test**

Create `tests/test-widget-icons.sh`:

```bash
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
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash tests/test-widget-icons.sh`
Expected: FAIL with messages for the two font glyphs, the About icon, the Close icon, the footer author icon, and the disconnected Bluetooth icon.

- [ ] **Step 3: Replace the About font glyph**

In `plasmoid/contents/ui/HeadsetPopup.qml`, on the `aboutButton` tool button, keep `display: PlasmaComponents3.AbstractButton.IconOnly` and `Accessible.name: "About XM Headset"`. Remove the custom `contentItem` label. Add:

```qml
icon.name: "help-about-symbolic"
icon.width: Kirigami.Units.iconSizes.smallMedium
icon.height: Kirigami.Units.iconSizes.smallMedium
```

- [ ] **Step 4: Replace the overlay Close font glyph**

On the overlay close tool button that has `Accessible.name: "Close"`, remove the custom `contentItem` label and add:

```qml
icon.name: "window-close-symbolic"
icon.width: Kirigami.Units.iconSizes.smallMedium
icon.height: Kirigami.Units.iconSizes.smallMedium
```

- [ ] **Step 5: Fix the footer author icon**

On the `authorButton` tool button, change:

```qml
icon.name: "internet-web-browser-symbolic"
```

to:

```qml
icon.name: "user-identity-symbolic"
```

Do not change the `onClicked` URL or the accessible name.

- [ ] **Step 6: Use the inactive Bluetooth icon when disconnected**

In the recovery header icon, change:

```qml
source: root.state === "none"
    ? "network-bluetooth-symbolic"
    : "dialog-warning-symbolic"
```

to:

```qml
source: root.state === "none"
    ? "network-bluetooth-inactive-symbolic"
    : "dialog-warning-symbolic"
```

- [ ] **Step 7: Run the contract test to verify it passes**

Run: `bash tests/test-widget-icons.sh`
Expected: `PASS: widget icon map is consistent`

- [ ] **Step 8: Lint the touched QML**

Run:

```bash
qmllint plasmoid/contents/ui/HeadsetPopup.qml \
        plasmoid/contents/ui/ProfileCard.qml \
        plasmoid/contents/ui/MicTestPanel.qml \
        plasmoid/contents/ui/main.qml
```

Expected: no output and exit code 0.

- [ ] **Step 9: Render the changed states and inspect them**

Run:

```bash
mkdir -p /tmp/opencode/xm-preview
QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=KDE \
  qml6 preview/preview.qml -- --state=about --scale=2 \
  --out=/tmp/opencode/xm-preview/about-after.png
QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=KDE \
  qml6 preview/preview.qml -- --state=none --scale=2 \
  --out=/tmp/opencode/xm-preview/none-after.png
QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=KDE \
  qml6 preview/preview.qml -- dark --state=about --scale=2 \
  --out=/tmp/opencode/xm-preview/about-dark-after.png
QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=KDE \
  qml6 preview/preview.qml -- dark --state=none --scale=2 \
  --out=/tmp/opencode/xm-preview/none-dark-after.png
```

Check that the About and Close icons are monochrome, correctly sized, and aligned with the neighbouring header controls; check that the disconnected Bluetooth icon reads as inactive but not as an error.

- [ ] **Step 10: Run the full test suite**

Run:

```bash
bash tests/test-widget-config.sh
bash tests/test-generic-headset.sh
bash tests/test-live-waveform.sh
bash tests/test-profile-switch.sh
bash tests/test-widget-icons.sh
```

Expected: every test prints `PASS` or its normal success summary, and the command exits 0.

- [ ] **Step 11: Reinstall the local widget without restarting Plasmashell**

Run:

```bash
./install-widget.sh
```

Then clear the QML cache if the installer does not do it. Do not restart Plasmashell automatically.

- [ ] **Step 12: Commit**

```bash
git add plasmoid/contents/ui/HeadsetPopup.qml tests/test-widget-icons.sh \
        docs/superpowers/specs/2026-10-25-widget-icons-design.md \
        docs/superpowers/plans/2026-10-25-widget-icons.md
git commit -m "fix(widget): use consistent symbolic icons"
```

---

### Task 2: Refresh the preview assets

**Files:**
- Modify: `assets/screenshot-light.png`
- Modify: `assets/screenshot-dark.png`
- Modify: `assets/screenshot-waveform.png`
- Modify: `assets/screenshot-modal.png`
- Modify: `assets/widget-screenshot.png`
- Modify: `assets/widget-demo.gif`
- Modify: `assets/demo.gif`

**Interfaces:**
- Consumes: the updated `HeadsetPopup.qml` from Task 1.
- Produces: README screenshots that match the installed widget.

- [ ] **Step 1: Regenerate the screenshots and GIF**

Run: `./preview/render-assets.sh`
Expected: the script prints each rendered state and ends with `done: assets`.

- [ ] **Step 2: Verify the assets changed and are valid**

Run:

```bash
git status --short assets
file assets/screenshot-modal.png assets/widget-demo.gif
```

Expected: the expected image files are modified, and `file` identifies them as PNG and GIF data.

- [ ] **Step 3: Inspect the About and main screenshots**

Open `assets/screenshot-modal.png` and `assets/widget-screenshot.png` and confirm the new Breeze icons are visible and correctly coloured.

- [ ] **Step 4: Commit**

```bash
git add assets
git commit -m "docs(assets): refresh widget previews for icon polish"
```
