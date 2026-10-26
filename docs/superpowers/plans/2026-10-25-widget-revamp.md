# Widget Revamp: Live Audio Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the widget popup around a live microphone instrument, make the panel and action icons state-accurate, and give the About repo link a real GitHub mark.

**Architecture:** `MicTestPanel.qml` grows from a card into the 9.8-grid-unit hero, with a compact `Chip.qml` shared by the profile, battery and verdict chips. `HeadsetPopup.qml` is reordered to header → hero → cards → maintenance → footer, `ProfileCard.qml` becomes a horizontal 3.2-grid-unit card, and `main.qml` maps connection state to the compact glyph. A new `GitHubIcon.qml` draws the mark with `QtQuick.Shapes`, so it tints without an image asset.

**Tech Stack:** QML, Qt 6, Plasma 6, Kirigami, `QtQuick.Shapes`, the Breeze icon theme, `qml6`, shell and Python 3.

**Spec:** `docs/superpowers/specs/2026-10-25-widget-revamp-design.md`

## Global Constraints

- Plasma 6 / Kirigami only; no new package or runtime dependency.
- Breeze symbolic icons for every action except the single GitHub brand mark.
- Live levels exist only during a 5 s test; never render `LIVE` outside a result.
- Keep the popup’s 22 × 28 grid-unit preferred size and the existing signals.
- Do not change `xm`, PipeWire, BlueZ, configuration keys, or command execution.
- Do not push. Work stays on `feature/widget-v2`.
- All existing tests must keep passing.

## Review Focus

- Headset absent (`none`): recovery card, no hero/cards, compact icon is the inactive Bluetooth glyph. Pinned by Task 2’s test and the `none` render.
- Unreadable profile (`error`): warning glyph, red tint, no stale verdict. Pinned by Task 2’s test and the `error` render.
- Music profile (`a2dp`): test still switches to Call first; panel stays a headset with the music accent. Pinned by the `a2dp` render and `test-profile-switch.sh`.
- Mic-test failure or malformed JSON: `NO MIC`, error glyph, no `NaN` / `undefined` in the readout. Pinned by Task 4’s `micerror` fixture.
- Narrow popup and light theme: no clipped chips or dBFS text, legible verdict colours. Pinned by Task 6’s light renders.
- Connected popup with a success message: footer stays inside 505 px. Pinned by Task 5’s `notice` fixture.

---

### Task 1: GitHub mark for the repository link

**Files:**
- Create: `plasmoid/contents/ui/GitHubIcon.qml`
- Modify: `plasmoid/contents/ui/HeadsetPopup.qml` (`aboutRepoButton`, around line 828)
- Test: `tests/test-widget-icons.sh`
- Commit: `docs/superpowers/specs/2026-10-25-widget-revamp-design.md` and this plan with the code change.

**Interfaces:**
- Consumes: `Kirigami.Theme.textColor`, `Kirigami.Units.iconSizes.small`, existing `root.fgColor`.
- Produces: `GitHubIcon { color: color; implicitWidth: 16; implicitHeight: 16 }`, used by later tasks only in About.

- [ ] **Step 1: Extend the icon contract test**

Append to `tests/test-widget-icons.sh` inside the Python block, before `if errors:`:

```python
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
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `./tests/test-widget-icons.sh`
Expected: FAIL with `missing .../GitHubIcon.qml`.

- [ ] **Step 3: Create `plasmoid/contents/ui/GitHubIcon.qml`**

```qml
// Monochrome GitHub mark drawn as a Shape, so it follows the theme colour
// without shipping light/dark image variants. ViewBox: 16 x 16.
import QtQuick
import QtQuick.Shapes
import org.kde.kirigami as Kirigami

Item {
    id: icon

    property color color: Kirigami.Theme.textColor

    implicitWidth: 16
    implicitHeight: 16

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        transform: Scale {
            xScale: icon.width / 16
            yScale: icon.height / 16
            origin.x: 0
            origin.y: 0
        }

        ShapePath {
            fillColor: icon.color
            strokeColor: "transparent"
            PathSvg {
                path: "M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27s1.36.09 2 .27c1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.01 8.01 0 0 0 16 8c0-4.42-3.58-8-8-8Z"
            }
        }
    }
}
```

- [ ] **Step 4: Replace the repo button icon**

In `aboutRepoButton`, delete `icon.name: "internet-web-browser-symbolic"` and `display: ...`, and add:

```qml
contentItem: RowLayout {
    spacing: Kirigami.Units.smallSpacing

    GitHubIcon {
        Layout.preferredWidth: Kirigami.Units.iconSizes.small
        Layout.preferredHeight: Kirigami.Units.iconSizes.small
        color: Kirigami.Theme.textColor
        opacity: 0.9
    }

    PlasmaComponents3.Label {
        text: "GitHub repo"
        font: Kirigami.Theme.smallFont
    }
}
```

Keep `text: "GitHub repo"` on the button for semantics and keep its tooltip and `Accessible.name`.

- [ ] **Step 5: Run the test and lint**

Run: `./tests/test-widget-icons.sh && qmllint plasmoid/contents/ui/GitHubIcon.qml plasmoid/contents/ui/HeadsetPopup.qml`
Expected: `PASS: widget icon map is consistent`, no lint output.

- [ ] **Step 6: Render the About overlay and inspect the mark**

```bash
mkdir -p /tmp/opencode/xm-revamp
QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=KDE \
  qml6 preview/preview.qml -- dark --state=about --scale=2 \
  --out=/tmp/opencode/xm-revamp/about.png
```

Open the image. Expected: a black/theme-coloured GitHub cat at 16 px beside `GitHub repo`, no blue globe, no clipping.

- [ ] **Step 7: Commit**

```bash
git add docs/superpowers/specs/2026-10-25-widget-revamp-design.md \
        docs/superpowers/plans/2026-10-25-widget-revamp.md \
        plasmoid/contents/ui/GitHubIcon.qml plasmoid/contents/ui/HeadsetPopup.qml \
        tests/test-widget-icons.sh
git commit -m "feat(widget): add a GitHub mark to the About link"
```

---

### Task 2: State-accurate panel and header glyphs

**Files:**
- Modify: `plasmoid/contents/ui/main.qml` (`compactRepresentation`, around line 214)
- Modify: `plasmoid/contents/ui/HeadsetPopup.qml` (header icon, `readonly property string headerIcon`)
- Modify: `plasmoid/README.md` (panel state table)
- Test: `tests/test-widget-icons.sh`

**Interfaces:**
- Consumes: `headsetState`, `state`, `stateColor`.
- Produces: `main.compactIconSource: string`, `HeadsetPopup.headerIcon: string`; later tasks bind no new names from these.

- [ ] **Step 1: Extend the test**

Add before `if errors:`:

```python
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
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `./tests/test-widget-icons.sh`
Expected: FAIL with `main.qml must define compactIconSource`.

- [ ] **Step 3: Implement both mappings**

In `main.qml`, add beside `stateColor`:

```qml
readonly property string compactIconSource: {
    switch (headsetState) {
        case "none":  return "network-bluetooth-inactive-symbolic"
        case "error": return "dialog-warning-symbolic"
        default:      return "audio-headset-symbolic"
    }
}
```

Change `compactIcon.source` to `root.compactIconSource`. Keep the colour and the 0.5 busy opacity.

In `HeadsetPopup.qml`, add beside `stateColor`:

```qml
readonly property string headerIcon: {
    switch (state) {
        case "none":  return "network-bluetooth-inactive-symbolic"
        case "error": return "dialog-warning-symbolic"
        default:      return "audio-headset-symbolic"
    }
}
```

Change the header `Kirigami.Icon.source` to `root.headerIcon`; leave the live colour badge alone.

- [ ] **Step 4: Run the test and lint**

Run: `./tests/test-widget-icons.sh && qmllint plasmoid/contents/ui/main.qml plasmoid/contents/ui/HeadsetPopup.qml`
Expected: PASS, no lint output.

- [ ] **Step 5: Update the panel table in `plasmoid/README.md`**

Replace the colour-only table under “The panel colour follows that token” with:

```markdown
| State | Panel glyph | Colour |
|:------|:------------|:-------|
| `hfp` (call) | headset | green |
| `a2dp` (music) | headset | theme highlight |
| `off` (standby) | headset | amber |
| `none` (headset off) | inactive Bluetooth | grey |
| `error` | warning triangle | red |
| busy / loading | headset, dimmed | amber / grey |
```

- [ ] **Step 6: Render `none` and `error` and inspect**

```bash
for s in none error; do
  QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=KDE \
    qml6 preview/preview.qml -- dark --state=$s --scale=2 \
    --out=/tmp/opencode/xm-revamp/$s.png
done
```

Expected: `none` shows the Bluetooth-off glyph; `error` shows the warning triangle, both in the header tile and panel; the recovery card matches.

- [ ] **Step 7: Commit**

```bash
git add plasmoid/contents/ui/main.qml plasmoid/contents/ui/HeadsetPopup.qml plasmoid/README.md tests/test-widget-icons.sh
git commit -m "feat(widget): make the panel glyph follow connection state"
```

---

### Task 3: Shared chip and battery glyph

**Files:**
- Create: `plasmoid/contents/ui/Chip.qml`
- Modify: `plasmoid/contents/ui/HeadsetPopup.qml` (header layout, `batteryIcon`, `profileChipText`)
- Test: `tests/test-widget-icons.sh`

**Interfaces:**
- Consumes: `battery`, `hasBattery`, `codec`, `state`, `stateColor`.
- Produces: `Chip { text: string; iconName: string; tint: color; filled: bool }`, used by Tasks 4 and 5.

- [ ] **Step 1: Extend the test**

```python
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
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `./tests/test-widget-icons.sh`
Expected: FAIL with `missing .../Chip.qml`.

- [ ] **Step 3: Create `plasmoid/contents/ui/Chip.qml`**

```qml
// Small pill used for the profile, battery and mic verdict chips.
import QtQuick
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

Item {
    id: chip

    property string text: ""
    property string iconName: ""
    property color tint: Kirigami.Theme.textColor
    property bool filled: false

    implicitWidth: row.implicitWidth + Kirigami.Units.smallSpacing * 2
    implicitHeight: Kirigami.Units.gridUnit * 1.3

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: Qt.rgba(chip.tint.r, chip.tint.g, chip.tint.b,
                       chip.filled ? 0.16 : 0.07)
        border.width: 1
        border.color: Qt.rgba(chip.tint.r, chip.tint.g, chip.tint.b,
                              chip.filled ? 0.42 : 0.16)
    }

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: Kirigami.Units.smallSpacing * 0.6

        Kirigami.Icon {
            visible: chip.iconName.length > 0
            source: chip.iconName
            Layout.preferredWidth: Kirigami.Units.iconSizes.small
            Layout.preferredHeight: Kirigami.Units.iconSizes.small
            color: chip.tint
            opacity: 0.85
        }

        PlasmaComponents3.Label {
            text: chip.text
            font: Kirigami.Theme.smallFont
            color: chip.tint
            opacity: 0.9
        }
    }
}
```

- [ ] **Step 4: Add the header derivations**

In `HeadsetPopup.qml`:

```qml
readonly property string batteryIcon: {
    if (!hasBattery) return ""
    var step = Math.max(0, Math.min(100, Math.floor(battery / 10) * 10))
    return "battery-" + (step < 100 ? ("00" + step).slice(-3) : "100") + "-symbolic"
}

readonly property string profileChipText: {
    var suffix = codec.length > 0 ? " · " + codec : ""
    switch (state) {
        case "hfp":  return "Call" + suffix
        case "a2dp": return "Music" + suffix
        case "off":  return "Standby"
        default:     return ""
    }
}
```

- [ ] **Step 5: Replace the two-row header with the compact header**

Replace the header `Kirigami.Icon` size with a `gridUnit * 1.9` tinted rounded tile (`radius: Kirigami.Units.smallSpacing * 1.2`) and set the centered icon inside it to 18 × 18 px. Delete the 10 px state dot badge; the tile tint and profile chip carry state. Replace the name/state column and the codec/battery rectangles with:

```qml
PlasmaComponents3.Label {
    Layout.fillWidth: true
    text: root.deviceName
    font.bold: true
    font.pointSize: Kirigami.Theme.defaultFont.pointSize + 1
    elide: Text.ElideRight
    Accessible.name: root.deviceName + ". " + root.stateText
}

Chip {
    visible: root.showText && text.length > 0
    text: root.profileChipText
    tint: root.stateColor
    filled: true
}

Chip {
    visible: root.hasBattery
    text: root.battery + "%"
    iconName: root.batteryIcon
}

PlasmaComponents3.BusyIndicator {
    visible: root.busy && !root.testing
    running: visible
    Layout.preferredWidth: Kirigami.Units.gridUnit * 1.1
    Layout.preferredHeight: Kirigami.Units.gridUnit * 1.1
}
```

Keep the About button as the last child. Remove the old `stateText` label, `codecLabel`, `batteryLabel`, and their rectangles. The header `RowLayout` must keep `Layout.fillWidth: true`.

- [ ] **Step 6: Run the test, lint, and render**

```bash
./tests/test-widget-icons.sh && qmllint plasmoid/contents/ui/Chip.qml plasmoid/contents/ui/HeadsetPopup.qml
for s in hfp a2dp; do
  QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=KDE \
    qml6 preview/preview.qml -- dark --state=$s --scale=2 \
    --out=/tmp/opencode/xm-revamp/header-$s.png
done
```

Expected: PASS; `CALL · MSBC` / `MUSIC · LDAC` chips and a battery glyph at 90 %; the device name elides before the chips shrink.

- [ ] **Step 7: Commit**

```bash
git add plasmoid/contents/ui/Chip.qml plasmoid/contents/ui/HeadsetPopup.qml tests/test-widget-icons.sh
git commit -m "feat(widget): add semantic chips and a battery glyph"
```

---

### Task 4: Turn the mic test into the live-audio hero

**Files:**
- Modify: `plasmoid/contents/ui/MicTestPanel.qml` (whole layout)
- Modify: `preview/preview.qml` (state fixtures)
- Test: `tests/test-widget-icons.sh`

**Interfaces:**
- Consumes: `Chip` from Task 3; existing `testing`, `countdown`, `result`, `liveLevels`, `profileState`, `accentColor`.
- Produces: `statusIcon`, `stateChipText`, `peakText`, `durationText`, and a 9.8-grid-unit-tall panel that Task 5 moves above the cards.

- [ ] **Step 1: Extend the test**

```python
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
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `./tests/test-widget-icons.sh`
Expected: FAIL with `MicTestPanel must define statusIcon`.

- [ ] **Step 3: Add the hero derivations**

In `MicTestPanel.qml`, change the error branch of `verdictColor` to `redColor`, then add:

```qml
readonly property string statusIcon: {
    if (hasError) return "dialog-error-symbolic"
    if (testing) return "media-record-symbolic"
    switch (verdict) {
        case "live":   return "audio-input-microphone-symbolic"
        case "quiet":  return "audio-volume-low-symbolic"
        case "silent": return "audio-volume-muted-symbolic"
        default:       return "audio-input-microphone-symbolic"
    }
}

readonly property string stateChipText: {
    if (hasError) return "NO MIC"
    if (testing) return "LISTENING"
    switch (verdict) {
        case "live":   return "LIVE"
        case "quiet":  return "QUIET"
        case "silent": return "SILENT"
        default:       return "READY"
    }
}

readonly property string peakText: {
    if (testing) return String(countdown)
    if (hasResult && !hasError && !isNaN(Number(result.peak_dbfs)))
        return Number(result.peak_dbfs).toFixed(1).replace("-", "−")
    return "—"
}

readonly property string durationText: {
    if (testing) return ""
    if (hasResult && !hasError && !isNaN(Number(result.duration)))
        return Number(result.duration).toFixed(1) + " s"
    return "5 s"
}
```

Set `subtitle` for `live` to `"Call profile · microphone live"` so the big peak is not repeated.

- [ ] **Step 4: Replace the panel layout**

Set `implicitHeight: Kirigami.Units.gridUnit * 9.8`. Keep the tinted background/border bindings. Inside, replace the column with:

1. Header row: bold small `MIC INPUT` label (letter spacing 1.1, `verdictColor`), `Chip { text: stateChipText; tint: verdictColor; filled: true }`, spacer, `durationText` label.
2. Body row (`Layout.fillHeight: true`): left column with `peakText` at `defaultFont.pointSize + 12`, `verdictColor`, caption `testing ? "seconds left" : "dBFS peak"`; right waveform item filling the width, with the existing `testBars` / `result.levels` / `idleBars` logic.
3. Footer row: `Kirigami.Icon { source: statusIcon; color: verdictColor }` at 14 px, a column with bold `title` and elided `subtitle`, then the existing `ActionButton` (`Test` / `Again`, mic icon, `enabled: !testing`).

The header duration label uses `visible: durationText.length > 0`.

Waveform bar colour: `verdictColor` at 0.85 for a result, `accentColor` at 0.85 while testing, text colour at 0.14 idle (0.08 on error).

- [ ] **Step 5: Add the failure fixtures to `preview/preview.qml`**

In `previewState`, add `silent`, `quiet` and `micerror` to the `"hfp"` branch. In `previewTestResult` add:

```js
if (name === "quiet") {
    return {
        ok: true, verdict: "quiet", label: "QUIET",
        peak_dbfs: -48.0, duration: 5.0, levels: wave(0.08, 0.05)
    }
}
if (name === "micerror") {
    return {
        ok: false, verdict: "error", label: "NO MIC",
        message: "Switch to Call first, then try again.", levels: []
    }
}
```

Keep the existing `silent` fixture.

- [ ] **Step 6: Run the test, lint, and render every hero mode**

```bash
./tests/test-widget-icons.sh && qmllint plasmoid/contents/ui/MicTestPanel.qml preview/preview.qml
for s in testing live quiet silent micerror; do
  QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=KDE \
    qml6 preview/preview.qml -- dark --state=$s --scale=2 \
    --out=/tmp/opencode/xm-revamp/hero-$s.png
done
```

`quiet` uses the new fixture; no conditional setup is needed.

Expected: `LISTENING` + countdown, `LIVE` + `−17.8`, `QUIET`, `SILENT`, and `NO MIC` with the error glyph; no `NaN` / `undefined`.

- [ ] **Step 7: Commit**

```bash
git add plasmoid/contents/ui/MicTestPanel.qml preview/preview.qml tests/test-widget-icons.sh
git commit -m "feat(widget): turn the mic test into a live audio panel"
```

---

### Task 5: Restructure the popup around the hero

**Files:**
- Modify: `plasmoid/contents/ui/HeadsetPopup.qml` (main column order, restore icon, footer terminal glyph)
- Modify: `plasmoid/contents/ui/ProfileCard.qml` (compact horizontal card)
- Modify: `preview/preview.qml` (`notice` fixture)
- Test: `tests/test-widget-icons.sh`

**Interfaces:**
- Consumes: `MicTestPanel`, `Chip`, `GitHubIcon`, `headerIcon` from earlier tasks.
- Produces: final popup order; no new public names.

- [ ] **Step 1: Extend the test**

```python
mic_at = popup.find("MicTestPanel {")
card_at = popup.find("ProfileCard {")
if mic_at < 0 or card_at < 0 or mic_at > card_at:
    errors.append("the mic hero must appear above the profile cards")

restore = block('id: restoreButton', 1400)
if restore.count('"edit-reset-symbolic"') < 2:
    errors.append("Restore must use edit-reset-symbolic for icon and contentItem")
if "edit-undo-symbolic" in popup:
    errors.append("Restore must not use edit-undo-symbolic")
if '"utilities-terminal-symbolic"' not in popup:
    errors.append("the via xm footer must use utilities-terminal-symbolic")
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `./tests/test-widget-icons.sh`
Expected: FAIL with `the mic hero must appear above the profile cards`.

- [ ] **Step 3: Reorder the main column**

In `HeadsetPopup.qml`, set the main `ColumnLayout.spacing` to `Kirigami.Units.smallSpacing * 1.5`, then order the children:

```text
header
message
recovery
MicTestPanel (visible: root.connected)
ProfileCard row
maintenance row (Reconnect, Fix for meeting)
Item { Layout.fillHeight: true }
Kirigami.Separator
footer
```

Move the existing `MicTestPanel` block above the `ProfileCard` row; delete its old position below the cards. Delete the `"Fix = reconnect + Call..."` caption label. Keep the two `ActionButton`s and their tooltips.

- [ ] **Step 4: Restyle `ProfileCard.qml`**

Set `implicitHeight: Kirigami.Units.gridUnit * 3.2`. Replace the content column with a horizontal row:

```qml
contentItem: RowLayout {
    anchors.fill: parent
    anchors.leftMargin: Kirigami.Units.smallSpacing * 1.5
    anchors.rightMargin: Kirigami.Units.smallSpacing * 1.5
    spacing: Kirigami.Units.smallSpacing

    Kirigami.Icon {
        source: card.cardIcon
        Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
        Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
        color: card.isActive ? card.accentColor : Kirigami.Theme.textColor
        opacity: card.isActive ? 1.0 : 0.75
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 0
        PlasmaComponents3.Label { text: card.cardTitle; font.bold: true
            color: card.isActive ? card.accentColor : Kirigami.Theme.textColor }
        PlasmaComponents3.Label { text: card.cardSubtitle
            font: Kirigami.Theme.smallFont; opacity: card.isActive ? 0.9 : 0.62
            elide: Text.ElideRight }
    }

    Rectangle {
        visible: card.isActive
        Layout.preferredWidth: Kirigami.Units.gridUnit * 1.25
        Layout.preferredHeight: Kirigami.Units.gridUnit * 1.25
        radius: width / 2
        color: card.accentColor
        Kirigami.Icon {
            anchors.centerIn: parent
            width: Kirigami.Units.iconSizes.small
            height: width
            source: "checkmark-symbolic"
            color: (card.accentColor.r * 0.299 + card.accentColor.g * 0.587
                  + card.accentColor.b * 0.114) > 0.62 ? "#101314" : "#ffffff"
        }
    }
}
```

Keep the background, hover, press, focus, tooltip and `Accessible.name` behaviour.

- [ ] **Step 5: Fix Restore and the footer glyph**

Change both `edit-undo-symbolic` occurrences in `restoreButton` to `edit-reset-symbolic`. Add before the `via xm` label:

```qml
Kirigami.Icon {
    Layout.preferredWidth: Kirigami.Units.iconSizes.small
    Layout.preferredHeight: Kirigami.Units.iconSizes.small
    source: "utilities-terminal-symbolic"
    opacity: 0.45
}
```

- [ ] **Step 6: Add the `notice` fixture**

In `preview/preview.qml`, map `notice` to `hfp` in `previewState` and return `"Call profile on: mic + speaker both work."` from `previewMessage`. This is the success-message + connected case.

- [ ] **Step 7: Run the test, lint, and render the full layout**

```bash
./tests/test-widget-icons.sh && qmllint plasmoid/contents/ui/*.qml preview/preview.qml
for s in hfp a2dp none error notice; do
  QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=KDE \
    qml6 preview/preview.qml -- dark --state=$s --scale=2 \
    --out=/tmp/opencode/xm-revamp/layout-$s.png
done
QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=KDE \
  qml6 preview/preview.qml -- dark --state=live --scale=2 \
  --out=/tmp/opencode/xm-revamp/layout-live.png
```

Expected: hero above the cards; compact cards with icon, title, subtitle and active check; footer visible in every image, including `notice`; no clipped bottom edge.

- [ ] **Step 8: Commit**

```bash
git add plasmoid/contents/ui/HeadsetPopup.qml plasmoid/contents/ui/ProfileCard.qml preview/preview.qml tests/test-widget-icons.sh
git commit -m "feat(widget): restructure the popup around live audio"
```

---

### Task 6: Docs, screenshots, and the full check

**Files:**
- Modify: `README.md`
- Modify: `plasmoid/README.md` (only if the Task 2 table or About copy still needs it)
- Modify: `assets/screenshot-light.png`, `assets/screenshot-dark.png`, `assets/screenshot-waveform.png`, `assets/screenshot-modal.png`, `assets/widget-demo.gif`, `assets/demo.gif`
- Remove: `design-demos/` (untracked selection drafts)

**Interfaces:**
- Consumes: the finished popup.
- Produces: no code API.

- [ ] **Step 1: Fix the README copy**

- Change the “Click the **ⓘ** button” sentence to “Click the **?** button (About)”.
- Add `./tests/test-widget-icons.sh` to the Development Checks list.
- Update the “Device-aware header” bullet to mention the profile chip and battery glyph.
- Update the panel-icon bullet to say the glyph changes to inactive Bluetooth / warning when disconnected or unreadable.
- Mention the About overlay’s GitHub-marked repository link in the feature list.
- Extend the sentence after the test list so it says the icon test pins the semantic icon map, the state-aware panel glyph and the GitHub mark.

- [ ] **Step 2: Regenerate the real widget assets**

```bash
./preview/render-assets.sh
```

Inspect `assets/screenshot-light.png`, `screenshot-dark.png`, `screenshot-waveform.png`, `screenshot-modal.png`, and the five frames inside `widget-demo.gif`. Expected: the live-audio layout in all of them, the GitHub mark in the modal, the battery glyph at 90 %, and a visible footer.

- [ ] **Step 3: Run the full suite**

```bash
qmllint plasmoid/contents/ui/*.qml preview/preview.qml
./tests/test-widget-icons.sh
./tests/test-widget-config.sh
./tests/test-live-waveform.sh
./tests/test-profile-switch.sh
./tests/test-generic-headset.sh
```

Expected: every command exits 0; the icon test prints `PASS: widget icon map is consistent`.

- [ ] **Step 4: Remove the selection drafts**

```bash
rm -rf design-demos
git status --short
```

Expected: only the intended modified files and assets remain untracked/modified; no `design-demos/`.

- [ ] **Step 5: Commit**

```bash
git add README.md plasmoid/README.md assets tests preview
git commit -m "docs(assets): refresh widget previews for the live-audio revamp"
```

- [ ] **Step 6: Verify the branch state**

Run: `git log --oneline -7 && git status --short`
Expected: six new commits on top of `35fd3a9`, clean status, no push.
