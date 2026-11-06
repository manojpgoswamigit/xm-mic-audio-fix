# Changelog

## Unreleased

### Plasma widget
- Speaker and microphone volume sliders for the headset, with click-to-mute, keyboard and wheel control, shown only in Music and Call (mic live in Call only).

### CLI (`xm`)
- New `xm volume` and `xm mic-volume` commands: show, set (0-100), nudge (+N / -N), mute, unmute, toggle.
- `xm info` and `xm info --json` report the headset speaker and mic levels.

## 2.0.0

### Plasma widget
- Popup restructured around live audio, with a live waveform microphone test fed by real mic levels.
- Device header showing model, codec and battery, plus a link-reconnect action.
- Panel glyph follows connection state; semantic status chips and a battery glyph.
- Consistent symbolic icons, repaired config page, author credit and GitHub link.
- Refreshed screenshots and demo GIFs.

### CLI (`xm`)
- New commands: `info`, `doctor`, `reconnect`, and a JSON output mode for the mic test.
- Headset support is now model-agnostic: works with any standard Bluetooth headset, not just Sony XM.
- Profile switches return as soon as the profile is active.

## 1.0.0
- Initial release: `xm` CLI, WirePlumber config and KDE Plasma headset widget.
