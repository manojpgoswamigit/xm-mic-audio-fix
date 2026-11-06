# Volume Responsiveness Implementation Plan

> **For agentic workers:** Use executing-plans or subagent-driven-development. Steps use checkboxes for tracking.

**Goal:** Make slider input immediate and reduce the delay before the latest volume reaches the headset.

**Architecture:** Keep the existing volume runner and one in-flight command. Measure the cooldown from command dispatch and send the latest queued value as soon as both the cooldown and the in-flight command have finished.

**Tech stack:** Plasma 6 QML, Bash, PipeWire PulseAudio compatibility layer.

## 1. Reproduce and fix scheduling

- [x] Drive the production queue and timer handlers with a fake command that takes longer than 60 ms. Confirm the next command currently waits an extra timer interval after completion.
- [x] Start the 60 ms cooldown at dispatch. Have the completion and cooldown paths both attempt to drain the queue, with both gates checked in one place.
- [x] Verify that fast completions respect the cooldown and slow completions immediately dispatch the newest value. Exercise both speaker and mic keys.
- [ ] Exercise timeout recovery and late responses in a full applet integration test.

## 2. Remove visual lag

- [x] Add a Qt Quick test that moves the speaker slider by keyboard and checks that its handle reaches the target in the same event cycle.
- [x] Remove the position and fill-width animations. Keep hover, focus and mute feedback.
- [x] Verify drag, keyboard, wheel, mute, release and external read-back. Preserve the existing 0–100 range and headset-only targeting.

## 3. Check resource lifetime and confirm performance

- [x] Inspect executable source ownership, timer shutdown, queue size and waveform buffer size.
- [ ] Run an isolated Plasma host with a fake headset. Compare idle RSS, private memory, file descriptors and child processes after warm-up and several equal batches of volume changes. Check that resources return to steady state after each batch and that the last value wins.
- [ ] Repeat on real hardware when available. Measure dispatch-to-command completion and input-to-final audio update separately. Compare speaker and mic independently.
- [x] Run the regression suites and review the diff for unintended behavior changes. Investigate any sustained resource growth before claiming the leak check passed.

## Validation results

The keyboard test and a scheduler probe failed against the original code and passed after the fixes. All nine regression suites passed. A standalone QML probe used the production volume runner with a stub command and 500 inputs over five batches. At the five idle checkpoints, the queue was empty, there were no child processes, and private dirty memory stayed between 15,164 and 15,300 KiB. Full applet profiling and real audio latency measurements are still pending.

## Follow-up validation

- [x] Run the actual applet in an isolated Plasma host and drive its popup signals against a stateful command fixture. Cover Call, Music, connection and recovery, waveform and verdict, volume read-back after failure, and restore confirmation.
- [x] Reproduce a status poll replacing an in-flight snapshot and keep the richer snapshot in flight. Remove the redundant startup and popup-open status requests.
- [x] Share one BlueZ device response across the name, connection flag and battery fields in the connected-headset snapshot. The fake backend asserts one device query. On the connected headset, 15 interleaved runs per revision measured a median of 136.6 ms before and 120.2 ms after.
