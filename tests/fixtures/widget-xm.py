#!/usr/bin/env python3
"""Stateful test double for the widget's executable command boundary."""
import json
import sys
import time
from pathlib import Path

state_path = Path(__file__).with_name("state.json")
cmd, *args = sys.argv[1:]
with state_path.with_name("commands.log").open("a") as log:
    print(cmd, *args, file=log)
state = json.loads(state_path.read_text())

if cmd == "info":
    print(json.dumps(state))
elif cmd == "status":
    print(state["state"])
elif cmd in ("volume", "mic-volume"):
    time.sleep(0.09)
    channel = "speaker" if cmd == "volume" else "mic"
    if args[0] == "99":
        sys.exit("Fixture volume failure")
    if args[0] in ("mute", "unmute"):
        state[channel + "_muted"] = args[0] == "mute"
    else:
        state[channel + "_volume"] = int(args[0])
elif cmd == "test":
    assert state["state"] == "hfp"
    with Path(args[args.index("--live-file") + 1]).open("w") as meter:
        for _ in range(8):
            print("0.5", file=meter, flush=True)
            time.sleep(0.1)
    Path(meter.name).unlink()
    print(json.dumps(dict(ok=True, verdict="live", label="LIVE", peak_dbfs=-18, levels=[0.5] * 50)))
elif cmd in ("call", "music", "connect", "disconnect", "reconnect", "fix"):
    state["state"] = {
        "call": "hfp", "music": "a2dp", "connect": "a2dp", "disconnect": "none",
        "reconnect": "a2dp", "fix": "hfp",
    }[cmd]
    state["connected"] = state["state"] != "none"
    state["mic"] = state["state"] == "hfp"
elif cmd != "defaults-reset":
    sys.exit("Unexpected command: " + cmd)

if cmd not in ("info", "status", "test"):
    temp = state_path.with_suffix(".tmp")
    temp.write_text(json.dumps(state))
    temp.replace(state_path)
