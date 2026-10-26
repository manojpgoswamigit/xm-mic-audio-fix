# Widget revamp: Live audio

- **Date:** 2026-10-25
- **Status:** approved 2026-10-25; direction 3 selected, GitHub mark approved
- **Scope:** full widget redesign, icon accuracy, About link, docs and preview assets

## Intent

Rebuild the popup around the one thing a generic profile switcher cannot show:
whether the call microphone is actually alive. The live mic instrument becomes
the hero; profile switching and recovery sit underneath it. Every icon must
name exactly what it does, and the panel icon must describe the real connection
state instead of always drawing a headset.

## Selected direction

**3 · Live audio**, from `design-demos/` (drafts are selection artifacts and are
not shipped). The layout, spacing and hierarchy below follow that draft, with
one safety correction: Restore defaults stays in the footer instead of becoming
an equal-weight button beside Fix.

## Layout

Top to bottom, inside the popup:

1. **Header** — 34 px state-tinted icon tile, device name, profile chip,
   battery chip, About button.
2. **Message** — the existing transient banner, unchanged in behaviour.
3. **Recovery** — only for `none` / `error`, unchanged in behaviour.
4. **Hero** — `MicTestPanel`, visible when connected, 9.8 grid units tall.
5. **Profile cards** — compact horizontal Call / Music cards, 3.2 grid units.
6. **Maintenance** — Reconnect and Fix for meeting, side by side.
7. **Spacer**, separator, **footer** — Restore audio defaults, `via xm`, author.

The main column uses `Kirigami.Units.smallSpacing * 1.5` spacing. The popup keeps
its current 22 × 28 grid-unit preferred size, so a success message still fits
without clipping the footer.

The old status line and the “Fix = reconnect + Call” caption are removed; the
profile chip carries the profile, and the Fix tooltip carries the explanation.

## Header

- Icon source follows the connection state (see Panel icon).
- Profile chip text:
  - `hfp`: `Call` or `Call · <codec>`
  - `a2dp`: `Music` or `Music · <codec>`
  - `off`: `Standby`
  - otherwise: hidden
- Profile chip is also hidden when the `showText` setting is off.
- Battery chip shows a `battery-XXX-symbolic` glyph rounded down to the nearest
  10 %, plus `NN%`. No chip when the battery is unknown.

## Hero state matrix

| Mode | Chip | Big readout | Bars | Status icon | Status title |
|---|---|---|---|---|---|
| idle | `READY` | `—` | idle placeholder | `audio-input-microphone-symbolic` | Microphone check |
| testing | `LISTENING` | countdown | live levels | `media-record-symbolic` | Listening… |
| live | `LIVE` | peak dBFS | result levels | `audio-input-microphone-symbolic` | Microphone is working |
| quiet | `QUIET` | peak dBFS | result levels | `audio-volume-low-symbolic` | Microphone is very quiet |
| silent | `SILENT` | peak dBFS | result levels | `audio-volume-muted-symbolic` | No sound detected |
| error | `NO MIC` | `—` | dim placeholder | `dialog-error-symbolic` | No microphone available |

- The big readout caption is `seconds left` while testing, otherwise
  `dBFS peak`. Negative peaks use the typographic minus (`−`).
- Duration is shown at the header’s right edge: `5 s` idle, `N.N s` after a
  result, hidden while testing (the countdown owns the big readout).
- The footer row carries the status icon, title, subtitle and the
  `Test` / `Again` button.
- No continuous metering exists: live levels are only available during a 5 s
  test. The chip must never say `LIVE` outside a test result.

## Panel icon

| State | Compact icon |
|---|---|
| `loading`, `a2dp`, `hfp`, `off`, `busy` | `audio-headset-symbolic` |
| `none` | `network-bluetooth-inactive-symbolic` |
| `error` | `dialog-warning-symbolic` |

The profile distinction stays in the colour and the badge dot. The popup header
uses the same mapping.

## Icon contract

| Role | Icon |
|---|---|
| Connected device, Call profile | `audio-headset-symbolic` |
| Music profile | `audio-speakers-symbolic` |
| Mic idle / live verdict | `audio-input-microphone-symbolic` |
| Mic listening | `media-record-symbolic` |
| Mic quiet | `audio-volume-low-symbolic` |
| Mic silent | `audio-volume-muted-symbolic` |
| Mic error | `dialog-error-symbolic` |
| Reconnect | `view-refresh-symbolic` |
| Fix | `tools-symbolic` |
| Restore defaults | `edit-reset-symbolic` (not `edit-undo-symbolic`) |
| About | `help-about-symbolic` |
| Close | `window-close-symbolic` |
| Author | `user-identity-symbolic` |
| No headset | `network-bluetooth-inactive-symbolic` |
| Error state | `dialog-warning-symbolic` |
| Result message | `dialog-information-symbolic` |
| Active profile | `checkmark-symbolic` |
| Battery | `battery-XXX-symbolic` |
| CLI footer | `utilities-terminal-symbolic` |

## GitHub mark

Breeze has no GitHub brand glyph. Ship a single monochrome GitHub mark as a QML
`Shape` (`GitHubIcon.qml`) so it tints with `Kirigami.Theme` and stays crisp at
16 px without an image asset, `Qt5Compat`, or a `MultiEffect` dependency.

- Used only for the About overlay’s `GitHub repo` link.
- The author link stays `user-identity-symbolic`.
- Remove `internet-web-browser-symbolic` from the popup; a browser glyph on a
  GitHub link is the mismatch this revamp fixes.
- `assets/xmwidget.svg` remains the app/notification identity.

## Non-goals

- No change to `xm`, PipeWire, BlueZ, configuration keys, or command execution.
- No continuous microphone monitoring.
- No custom action-icon artwork besides the GitHub mark.
- No regeneration of `assets/cli-demo.gif` (it is terminal capture, not QML).
- No new package or runtime dependency.

## Review focus

1. Headset absent: no hero or cards, recovery card visible, panel shows the
   inactive Bluetooth glyph rather than a grey headset.
2. Unreadable profile: warning glyph and red tint, no stale mic verdict.
3. Music profile: hero still offers the test, which switches to Call first;
   panel stays a headset with the music accent.
4. Mic-test failure or malformed JSON: `NO MIC` and the error glyph, and the big
   readout never shows `NaN` / `undefined`.
5. Narrow popup and light theme: chips and the dBFS readout do not clip and the
   green / amber / red verdict colours stay legible.
6. Connected popup with a success message: the banner must not push the footer
   below the fixed popup height.
