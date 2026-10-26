# Widget icon consistency pass

- **Date:** 2026-10-25
- **Status:** approved 2026-10-25; consistency pass selected
- **Scope:** small UI polish

## Intent

Make the XM Headset Plasma widget use consistent, theme-aware Breeze symbolic icons instead of font glyphs and semantically mismatched icons. The widget should still read as native KDE software at a glance.

## Goals

- Replace the `ⓘ` About glyph with `help-about-symbolic`.
- Replace the `✕` Close glyph with `window-close-symbolic`.
- Use `user-identity-symbolic` for the footer author link.
- Use `network-bluetooth-inactive-symbolic` when the headset is disconnected.
- Keep the existing action icons: refresh for Reconnect, tools for Fix, undo for Restore, headset/speakers/microphone for the audio actions.

## Non-goals

- No layout, colour, spacing, or behaviour changes.
- No new icon assets or icon-theme dependency; Breeze already provides every icon used here.
- No changes to configuration, audio logic, or command execution.

## Constraints

- Plasma 6 / Kirigami symbolic icons only.
- Icons must inherit the widget palette and remain legible at panel and popup sizes.
- The existing preview harness must still render light and dark variants correctly.

## Approaches considered

1. **Consistency pass (selected)** — fix the two font glyphs, the author-link icon, and the disconnected Bluetooth state. Keeps the existing action icons.
   - Trade-off: conservative; does not make Fix or the `xm` CLI more expressive.
   - Why selected: it fixes the actual weak points without introducing new metaphors or clutter.
2. **Distinctive pass** — the above plus `tools-wizard-symbolic` for Fix and a terminal icon beside `via xm`.
   - Trade-off: more expressive, but the wand can read as “magic” and the footer gets busier.
3. **Minimal** — only replace the About and Close glyphs.
   - Trade-off: leaves the author-link globe and disconnected Bluetooth icon semantically wrong.

## Implementation

| Location | Change |
|---|---|
| `HeadsetPopup.qml` header About button | Use `icon.name: "help-about-symbolic"`; remove the custom text label. |
| `HeadsetPopup.qml` overlay Close button | Use `icon.name: "window-close-symbolic"`; remove the custom text label. |
| `HeadsetPopup.qml` footer author link | Change icon from `internet-web-browser-symbolic` to `user-identity-symbolic`. |
| `HeadsetPopup.qml` recovery header | When `state === "none"`, use `network-bluetooth-inactive-symbolic`; otherwise keep `dialog-warning-symbolic`. |

All other icon names remain unchanged.

## Verification

- `qmllint` on the touched QML files.
- Existing shell test suite (at minimum `tests/test-widget-config.sh`).
- Offscreen previews for disconnected, connected, and About states in light and dark themes.
- Reinstall the local widget and clear the QML cache; do not restart Plasmashell automatically.
