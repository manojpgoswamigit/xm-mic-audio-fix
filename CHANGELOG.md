# Changelog

## 2.2.0

### Plasma widget

- Speaker and microphone sliders update immediately with keyboard and wheel input.
- Queued volume changes dispatch sooner by overlapping the cooldown with the active command.
- The popup skips duplicate status requests and lets an active device refresh finish.

### CLI (`xm`)

- `xm info --json` reuses one BlueZ device response for the headset name, connection state and battery.

### Development

- Added an end-to-end Plasma suite for volume, profiles, the live mic test, connection recovery and restore confirmation.
- Added local hooks and a GitHub check for commit attribution.

## 2.1.0

### Plasma widget
- Speaker and microphone volume sliders for the headset, with click-to-mute, keyboard and wheel control, shown only in Music and Call (mic live in Call only).
- Connect / Disconnect button in the header (shortcut <kbd>D</kbd>) that keeps the headset paired.
- Compact popup: Call/Music first, a smaller idle mic check that expands while recording, and a header that keeps the device name and progress visible during actions.
- Better narrow-header layout, light-theme contrast and keyboard focus; refreshed screenshots and demo.

### CLI (`xm`)
- New `xm volume` and `xm mic-volume` commands: show, set (0-100), nudge (+N / -N), mute, unmute, toggle.
- `xm info` and `xm info --json` report the headset speaker and mic levels.
- New `xm connect`, `xm disconnect` and `xm toggle`, which verify the Bluetooth state and leave an already matching link alone.
- A standalone PulseAudio daemon running alongside pipewire-pulse is now detected and explained, in profile-switch errors and in `xm doctor`.

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
