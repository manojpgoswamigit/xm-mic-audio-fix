# XM Headset - Plasma panel widget

A tiny KDE Plasma 6 applet that puts `xm` one click away, right in the panel.

```
[ Call ]   -> HFP/mSBC   : microphone + speaker   (before a meeting)
[ Music ]  -> A2DP/LDAC : hi-fi output, no mic   (after a meeting)
```

plus `Test mic`, `Reset link`, `Fix`, and a live status indicator.

## What it is (and is not)

It is a **click-runner and status light**. It does not touch PipeWire, BlueZ or
WirePlumber itself: every button just runs the `xm` command that
`install.sh` already put in `~/.local/bin`.

That is deliberate. It means:

- The applet can never corrupt your audio stack. Worst case a click does nothing.
- `xm call`, `xm music`, `xm fix` ... keep working exactly as before, from the
  terminal, with or without the widget installed.
- Uninstalling the widget is always safe, because it owns nothing important.

## Install

```bash
./install-widget.sh          # from the repo root
```

Then add it to the panel:

> right-click the panel -> **Add Widgets** -> search `XM` -> drag **XM Headset**

`install.sh` also accepts `WITH_WIDGET=1 ./install.sh` to do both at once.

## Requirements

| Needed | Why |
|:-------|:----|
| Plasma 6 | `PlasmoidItem`, `org.kde.plasma.*` QML modules |
| `kpackagetool6` | installs/removes the applet package |
| `xm` in `~/.local/bin` | what the buttons actually run |
| one SVG renderer | `rsvg-convert` or `magick` or `convert`, to rasterise the icon at 16-256px. Without one, the SVG is still installed and the widget works, just less crisp. |

No new packages, no root, no daemon.

## How the applet works

`xm status --machine` prints exactly one token, so the panel can poll cheaply:

```
a2dp    headset connected, hi-fi profile
hfp     headset connected, hands-free profile
none    no Bluetooth audio card found (headset off)
error   dependency missing or the audio stack could not be queried
```

The panel colour follows that token:

| State | Panel icon |
|:------|:-----------|
| `hfp` (call) | green |
| `a2dp` (music) | theme highlight |
| `none` (headset off) | grey |
| busy / error | amber / red |

The human-readable `xm status` output is unchanged.

## Configuration

Right-click the applet -> **Configure**:

| Option | Default | Meaning |
|:-------|:--------|:--------|
| Command | `~/.local/bin/xm` | path to `xm`, if it is somewhere unusual |
| Refresh interval | 2 s | how often the panel polls `xm status --machine`. `xm` answers in ~15 ms, so 2 s costs nothing |
| Show profile and result text | on | status line + result messages in the popup |
| Ask before restoring defaults | on | confirmation before the one action that changes your audio config |
| Notifications | on | a notification when a slow action (`reset`, `fix`) finishes |

## Uninstall / rollback

Three graded levels via `uninstall-widget.sh`:

```bash
./uninstall-widget.sh --widget          # just the applet + its icons (default)
./uninstall-widget.sh --all             # applet + xm + WirePlumber config
./uninstall-widget.sh --restore-config  # only restore the WirePlumber config
./rollback.sh                           # = --all --restart
```

`rollback.sh` is the "put me back" button. It removes the applet, the `xm`
command and the WirePlumber drop-in, restores whatever WirePlumber config you
had before, and restarts plasmashell. Afterwards `which xm` is empty and
automatic A2DP/HFP switching is back on.

## Safety gates

The installer and uninstaller are both written on the assumption that they will
one day be interrupted mid-run.

- **Never root.** Both refuse to run as root.
- **Manifest-driven.** `install-widget.sh` records every path it creates in
  `~/.local/state/xm-widget/manifest`; the uninstaller removes exactly those
  paths, and refuses anything outside `$HOME` or containing `..`, `//` or a space.
- **Backup before change.** The pre-install WirePlumber config is copied to
  `~/.local/state/xm-widget/backups/wireplumber/<timestamp>/`, with an
  `info.env` recording whether it even existed, so a rollback restores *and*
  removes correctly in both directions.
- **Panel cleaned before package.** The applet is removed from all panels by
  DBus *before* the package is deleted, so plasmashell never holds a reference
  to something that no longer exists.
- **No silent restarts.** The installer never restarts plasmashell. Only
  `rollback.sh --restart` does, and only if you asked for it.
- **QML cache cleared.** A stale `~/.cache/plasmashell/qmlcache` is the usual
  cause of "my change did not show up"; both scripts clear it.

## Troubleshooting

**The widget does not appear in "Add Widgets".**
Run `./install-widget.sh` again, then re-open the widget explorer.

**I changed the QML and nothing happened.**
Clear `~/.cache/plasmashell/qmlcache`, then
`kquitapp6 plasmashell && kstart plasmashell`.

**The icon is missing.**
Re-run `kbuildsycoca6 --noincredible`, or install `librsvg`/`imagemagick` and
re-run `./install-widget.sh`.

**It says "no headset" when the headset is connected.**
The applet trusts `xm status --machine`. Run that by hand; if it prints `none`
while the headset is connected, `xm` cannot see the Bluetooth card, which is an
audio-stack issue, not a widget issue.
