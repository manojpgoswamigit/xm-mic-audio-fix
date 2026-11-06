#!/usr/bin/env bash
# Run the actual applet in a separate Plasma host with a fake headset.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
python3 - <<'PY'
import json
import os
import shutil
import signal
import subprocess
import tempfile
import time
from pathlib import Path

for command in ("plasmawindowed", "dbus-run-session"):
    if not shutil.which(command):
        raise SystemExit(f"{command} is required for the Plasma integration test.")

with tempfile.TemporaryDirectory(prefix="xm-widget-e2e-") as directory:
    root = Path(directory)
    plugin_id = "com.manojpgoswami.xmwidget"
    package = root / "data/plasma/plasmoids" / plugin_id
    shutil.copytree("plasmoid", package)
    helper = root / "xm"
    shutil.copyfile("tests/fixtures/widget-xm.py", helper)
    helper.chmod(0o700)
    (root / "state.json").write_text(json.dumps(dict(
        state="a2dp", device="Fixture headset", connected=True, mic=False,
        speaker_volume=54, speaker_muted=False, mic_volume=70, mic_muted=False,
    )))
    main = package / "contents/ui/main.qml"
    source = main.read_text()
    start = source.index("    readonly property string xmBin:")
    end = source.index("\n    }", start) + len("\n    }")
    source = source[:start] + f"    readonly property string xmBin: {json.dumps(str(helper))}" + source[end:]
    source = source.replace("id: popup\n", "id: popup\n        property alias testPopup: headsetPopup\n", 1)
    source = source.replace('if (!cfgNotify) {', 'if (e2eTimer.running || !cfgNotify) {', 1)
    main.write_text(source.rstrip()[:-1] + Path("tests/fixtures/widget-e2e.qml.inc").read_text() + "}\n")
    for name in ("config", "cache", "runtime", "tmp"):
        (root / name).mkdir(mode=0o700)
    env = dict(os.environ, XDG_DATA_HOME=str(root / "data"), XDG_CONFIG_HOME=str(root / "config"),
               XDG_CACHE_HOME=str(root / "cache"), XDG_RUNTIME_DIR=str(root / "runtime"),
               QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software", TMPDIR=str(root / "tmp"),
               QT_FORCE_STDERR_LOGGING="1", QT_LOGGING_RULES="qml.debug=true")
    command = ["dbus-run-session", "--", "plasmawindowed", plugin_id]
    log = root / "plasma.log"
    with log.open("w") as stream, subprocess.Popen(
        command, env=env, stdout=stream, stderr=subprocess.STDOUT, start_new_session=True,
    ) as process:
        try:
            deadline = time.monotonic() + 18
            while process.poll() is None and time.monotonic() < deadline:
                output = log.read_text()
                if "XM_E2E_PASS" in output or "XM_E2E_FAIL" in output:
                    break
                time.sleep(0.05)
        finally:
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGTERM)
                try:
                    process.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait()
    output = log.read_text()
    commands = (root / "commands.log")
    trace = commands.read_text().splitlines() if commands.exists() else []
    if "XM_E2E_PASS" not in output or "XM_E2E_FAIL" in output:
        raise SystemExit(output + "\nCommands:\n" + "\n".join(trace))
    if any(error in output for error in ("ReferenceError", "TypeError", "Binding loop")):
        raise SystemExit(output)
    writes = [line for line in trace if line.startswith(("volume ", "mic-volume "))]
    assert writes == ["volume 20", "volume 60", "mic-volume 35", "volume mute", "volume 99", "volume unmute"], writes
    assert trace.count("defaults-reset") == 1, trace
    state = json.loads((root / "state.json").read_text())
    assert state["speaker_volume"] == 60 and state["mic_volume"] == 35, state
    assert not list((root / "tmp").glob("xm-live-*"))
    print("PASS: Plasma applet, command wiring, coalescing, read-back, waveform, profiles, recovery and confirmation")
PY
