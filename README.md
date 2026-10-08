<div align="center">

# 🎧 xm

### Stop your Sony XM headset from losing its mic in meetings

**One command. `xm call` for the meeting. `xm music` when it's done.**

*Fixes Teams / Zoom / WebRTC mic dropouts and mid-call audio glitches on PipeWire*

<p>
  <img alt="Platform" src="https://img.shields.io/badge/platform-Linux%20%7C%20PipeWire-blue?style=flat-square">
  <img alt="Distros" src="https://img.shields.io/badge/tested%20on-Arch%20%7C%20CachyOS-1793d1?style=flat-square&logo=archlinux&logoColor=white">
  <img alt="License" src="https://img.shields.io/badge/license-MIT-green?style=flat-square">
  <img alt="Devices" src="https://img.shields.io/badge/devices-WH%2FWF--1000XM3%20%7C%20XM4%20%7C%20XM5-6f42c1?style=flat-square">
</p>

![demo](assets/demo.gif)

</div>

---

## 😤 The problem

Your headphones sound **amazing** for music. Then you join a meeting and it all falls apart.

The microphone cuts out. The audio glitches. People tell you *"you're silent"* while your headset insists it's connected. If you've lived this, you know the pain:

> *"Why does my Sony WH-1000XM5 lose its microphone in Teams but work perfectly in Spotify?"*

Here's the ugly truth: **it's not a bug you can patch.** Bluetooth simply has two audio profiles, and only one carries a microphone.

<div align="center">
  <img src="assets/how-it-works.png" alt="How it works" width="760">
</div>

| Profile | Used for | Speaker | Microphone | Quality |
|:--------|:---------|:-------:|:----------:|:--------|
| **A2DP**  | Music | ✅ | ❌ | Hi-fi (LDAC/AAC) |
| **HFP/HSP** | Calls | ✅ | ✅ | Voice-grade (mono) |

When a meeting opens, Linux must flip from A2DP to HFP so your mic works. By default **WirePlumber does this automatically, the instant any app touches the mic** - even Teams/Zoom merely *peeking* at devices when they launch. That split-second flip, repeated a few times, is your *"audio cuts out"* moment. On the XM5 that flip can even **die halfway**, leaving a mic that looks connected but sends pure silence.

## 💡 The fix

Two tiny, fully-reversible pieces:

1. **`51-bt-calls.conf`** - a WirePlumber drop-in that **turns off** the automatic A2DP↔HFP flapping, and enables wideband (mSBC) speech + hardware volume.
2. **`xm`** - a small command that switches the profile **once, on purpose**, when *you* decide.

No kernel patches. No downgrades. No extra packages. Just calmer Bluetooth.

---

## ⚡ Quick start

```bash
# 1. Get the repo
git clone https://github.com/manojpgoswamigit/xm-mic-audio-fix.git
cd xm-mic-audio-fix

# 2. Run the installer (user-level, no sudo)
chmod +x install.sh xm.sh uninstall.sh
./install.sh

# 3. Open a new terminal, then:
xm call        # join your meeting
xm music       # back to hi-fi when you're done
```

The installer drops `xm` into `~/.local/bin` and the config into
`~/.config/wireplumber/wireplumber.conf.d/`, then restarts WirePlumber.

<details>
<summary><b>Don't have the audio stack? Install it first</b></summary>

```bash
sudo pacman -S --needed pipewire pipewire-pulse wireplumber bluez bluez-utils
```

</details>

---

## 🎮 Commands

| Command | What it does | When to use it |
|:--------|:-------------|:---------------|
| `xm call` | Switch to **HFP/mSBC** - mic **and** speaker work | 🎙️ **Before** a meeting |
| `xm music` | Switch to **A2DP/LDAC** - hi-fi, no mic | 🎵 **After** a meeting |
| `xm test` | Records 5s and reports **LIVE / QUIET / SILENT** | 🩺 Mic troubleshooting |
| `xm reset` | Reconnect the headset to clear a dead link | 🔧 Mic looks connected but isn't |
| `xm fix` | `reset` + `call` in one shot | 🚨 Pre-meeting one-liner |
| `xm status` | Show the current profile | 🔍 Quick check |

> 💡 **Tip:** In Teams/Zoom, set **Speaker** and **Microphone** both to your headset.

## 🩺 "People can't hear me!"

Run this and talk for 5 seconds:

```bash
xm test
```

| Output | Meaning | Fix |
|:-------|:--------|:----|
| `VERDICT: LIVE` | 🎉 Mic works | Nothing. You're good. |
| `VERDICT: QUIET` | Signal is low | Move closer / raise mic volume |
| `VERDICT: SILENT` | Link is dead | `xm reset`, then `xm test` again |

If it's *still* silent after a reset, the SCO link is stuck - disconnect the
headset from Bluetooth settings once and reconnect. A small number of XM5 units
have a firmware quirk here that no Linux-side fix fully resolves.

---

## 🗑️ Uninstall

```bash
./uninstall.sh
```

Removes both pieces and restores WirePlumber's default auto-switching. Nothing
left behind.

## ⚠️ Honest expectations

- Mic quality drops to **voice-grade** in `call` mode. That's physics - LDAC
  can't carry a mic. Windows does exactly the same.
- The win is **switching once, on purpose**, instead of the OS flapping 5 times
  mid-call. That single change is what kills the "audio cuts out" symptom.

## 📁 What's inside

| File | Purpose |
|:-----|:---------|
| `install.sh` | Installs `xm` + the WirePlumber config |
| `uninstall.sh` | Removes both, restores defaults |
| `xm.sh` | The `xm` command (switcher + mic test + rescue) |
| `51-bt-calls.conf` | WirePlumber drop-in (disables auto HFP switching) |
| `assets/` | Demo GIF + how-it-works diagram |

## ✅ Supported & tested

- **Headsets:** Sony WH-1000XM3 / XM4 / XM5, WF-1000XM3 / XM4 / XM5 (and most Bluetooth headsets)
- **Distros:** Arch, CachyOS, and any PipeWire-based Linux
- **Stack:** PipeWire 1.x + WirePlumber 0.5.x + BlueZ

## 📄 License

[MIT](LICENSE) - do whatever you want, no warranty.

---

<div align="center">
  <sub>Built out of frustration. Shared so you don't have to suffer the same Friday-standup silence.</sub>
</div>
