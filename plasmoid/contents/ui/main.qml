// =============================================================================
//  XM Headset - Plasma 6 panel applet
// =============================================================================
//  One click on the panel switches the XM Bluetooth headset between:
//
//      Call   -> HFP/mSBC  : microphone AND speaker work (before a meeting)
//      Music  -> A2DP/LDAC : hi-fi output, no mic        (after a meeting)
//
//  plus Reconnect / Fix helpers, a live microphone self-test with a real
//  waveform, a device/codec/battery header, and a safe "restore defaults"
//  escape hatch.
//
//  DESIGN RULES
//    * This applet never touches PipeWire / BlueZ itself. Every action is
//      delegated to ~/.local/bin/xm, so a bug here can only ever be a missed
//      click - it can never corrupt the audio stack.
//    * Missing xm, a missing headset or a crashed child process all degrade
//      into a visible, recoverable state. Nothing throws.
//    * Exactly one command runs at a time (single flight) and every command
//      has a hard timeout, so the UI can never get permanently stuck.
//    * Commands run through Plasma's own job runner, so no child process is
//      ever owned by plasmashell and nothing is left behind when the applet
//      is removed.
//    * Fast polling (`status --machine`, ~15 ms) keeps the panel icon live.
//      The richer `info --json` (~120 ms) is only fetched when the popup is
//      open and after an action, so Bluetooth is not woken every 2 seconds.
// =============================================================================

import QtQuick
import QtQuick.Layouts
import Qt.labs.platform as Labs

import org.kde.plasma.plasmoid
import org.kde.kirigami as Kirigami
import org.kde.plasma.extras as PlasmaExtras
import org.kde.plasma.plasma5support as Plasma5
import org.kde.notification as KNotify

PlasmoidItem {
    id: root

    // -------------------------------------------------------------------------
    // Configured behaviour (see contents/config/main.xml)
    // -------------------------------------------------------------------------
    readonly property string configuredPath: readCfg("xmPath", "")
    readonly property int    cfgPollSec: {
        var v = parseInt(readCfg("pollInterval", 2))
        return isNaN(v) ? 2 : Math.min(30, Math.max(1, v))
    }
    readonly property bool   cfgShowText: readCfg("showText", true) === true
                                          || readCfg("showText", true) === "true"
    readonly property bool   cfgConfirm:  readCfg("confirmReset", true) === true
                                          || readCfg("confirmReset", true) === "true"
    readonly property bool   cfgNotify:   readCfg("notifications", true) === true
                                          || readCfg("notifications", true) === "true"

    function readCfg(key, fallback) {
        if (!Plasmoid || !Plasmoid.configuration) {
            return fallback
        }
        var v = Plasmoid.configuration[key]
        return (v === undefined || v === null) ? fallback : v
    }

    // Resolved without relying on the shell expanding a leading "~": the
    // Plasma job runner does not guarantee that.
    function pathFromUrl(u) {
        return String(u).replace(/^file:\/\//, "")
    }

    readonly property string homeDir: pathFromUrl(
        Labs.StandardPaths.writableLocation(Labs.StandardPaths.HomeLocation))

    readonly property string tempDir: {
        var dir = pathFromUrl(
            Labs.StandardPaths.writableLocation(Labs.StandardPaths.TempLocation))
        return dir.length > 0 ? dir : "/tmp"
    }

    readonly property string xmBin: configuredPath.length > 0
        ? configuredPath
        : homeDir + "/.local/bin/xm"

    // -------------------------------------------------------------------------
    // State
    // -------------------------------------------------------------------------
    // headsetState: loading | a2dp | hfp | off | none | error | busy
    property string headsetState: "loading"
    property bool   busy:         false
    property bool   testing:      false
    property int    testCountdown: 5
    property string message:      ""
    property var    info:         ({})
    property var    testResult:   null
    property var    liveLevels:   []
    property string liveLevelFile: ""
    property bool   liveMeterBusy: false
    property int    liveMeterSeq:  0
    property string liveMeterSource: ""
    property real   liveMeterRequestAt: 0
    property int    liveLevelCount: 0

    property bool   confirmVisible: false
    property string confirmTitle:   ""
    property string confirmBody:    ""
    property string confirmAction:  ""

    function setMessage(msg) {
        root.message = msg
        if (msg.length > 0) {
            messageClearTimer.restart()
        } else {
            messageClearTimer.stop()
        }
    }

    Timer {
        id: messageClearTimer
        interval: 8000
        repeat: false
        onTriggered: root.message = ""
    }

    // one command at a time
    property var pending: null
    property int cmdSeq:  0

    // Reconnect can spend ~55 s on three full link attempts (plus Fix's profile
    // and mic-source waits), so the hard timeout must be generous.
    readonly property int actionTimeoutMs: 90000
    readonly property int statusTimeoutMs: 4000

    readonly property bool ableToRun:    !busy && !testing
    readonly property bool connected:    headsetState === "a2dp"
                                      || headsetState === "hfp"
                                      || headsetState === "off"
    readonly property bool ableToSwitch: ableToRun && connected

    // Adaptive theme detection: light text means a dark theme.
    readonly property bool isDark: (Kirigami.Theme.textColor.r * 0.299
                                  + Kirigami.Theme.textColor.g * 0.587
                                  + Kirigami.Theme.textColor.b * 0.114) > 0.5

    readonly property color colorA2dp: Kirigami.Theme.highlightColor
    readonly property color colorHfp:  isDark ? "#2cd483" : "#178a4c"
    readonly property color colorOff:  isDark ? "#9aa0a6" : "#59636e"
    readonly property color colorBusy: isDark ? "#e8a33d" : "#a85a00"
    readonly property color colorErr:  isDark ? "#e0553e" : "#c92a2a"

    readonly property color stateColor: {
        switch (headsetState) {
            case "a2dp":  return colorA2dp
            case "hfp":   return colorHfp
            case "off":   return colorBusy
            case "busy":  return colorBusy
            case "error": return colorErr
            case "none":  return colorOff
            default:      return colorOff
        }
    }

    // -------------------------------------------------------------------------
    // Tooltip
    // -------------------------------------------------------------------------
    readonly property string deviceName: {
        var n = (info || {}).device
        return (n && String(n).length > 0) ? String(n) : "XM Headset"
    }

    readonly property string tooltipDetail: {
        var codec = (info || {}).codec ? String(info.codec) : ""
        var battery = (info || {}).battery
        var extra = []
        if (codec.length > 0) extra.push(codec)
        if (battery !== null && battery !== undefined && !isNaN(Number(battery))) {
            extra.push(Number(battery) + "%")
        }
        return extra.length > 0 ? " · " + extra.join(" · ") : ""
    }

    readonly property string statusLine: {
        switch (headsetState) {
            case "a2dp":  return "Music profile (A2DP), no microphone"
            case "hfp":   return "Call profile (HFP), mic + speaker ready"
            case "off":   return "Connected, audio profile standby"
            case "busy":  return testing ? "Testing the microphone…" : "Working…"
            case "none":  return "No Bluetooth headset found"
            case "error": return "xm could not report a profile"
            default:      return "Checking…"
        }
    }

    toolTipMainText: deviceName
    toolTipSubText:  statusLine + tooltipDetail

    // -------------------------------------------------------------------------
    // Compact representation: tinted headset + state badge
    // -------------------------------------------------------------------------
    compactRepresentation: Item {
        id: compactHolder
        Accessible.name: root.deviceName + ". " + root.statusLine

        Kirigami.Icon {
            id: compactIcon
            anchors.centerIn: parent
            width:  Math.min(parent.width, parent.height) * 0.82
            height: width
            source: "audio-headset-symbolic"
            color:  root.stateColor
            opacity: (root.busy || root.testing) ? 0.5 : 1.0
            Behavior on opacity { NumberAnimation { duration: 220 } }
            Behavior on color   { ColorAnimation  { duration: 200 } }
        }

        Rectangle {
            width:  Math.max(6, Math.min(parent.width, parent.height) * 0.22)
            height: width
            radius: width / 2
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.rightMargin: 1
            anchors.bottomMargin: 1
            color: root.stateColor
            border.width: 1
            border.color: Kirigami.Theme.backgroundColor
            Behavior on color { ColorAnimation { duration: 200 } }
        }
    }

    // -------------------------------------------------------------------------
    // Full representation: all of the drawing lives in HeadsetPopup.qml
    // -------------------------------------------------------------------------
    fullRepresentation: PlasmaExtras.Representation {
        id: popup

        Layout.minimumWidth:  Kirigami.Units.gridUnit * 20
        Layout.preferredWidth: Kirigami.Units.gridUnit * 22
        Layout.minimumHeight: Kirigami.Units.gridUnit * 26
        Layout.preferredHeight: Kirigami.Units.gridUnit * 28

        Kirigami.Theme.colorSet: Kirigami.Theme.View

        HeadsetPopup {
            anchors.fill: parent
            state:         root.headsetState
            busy:          root.busy
            testing:       root.testing
            countdown:     root.testCountdown
            message:       root.message
            info:          root.info
            testResult:    root.testResult
            liveLevels:    root.liveLevels
            showText:      root.cfgShowText
            confirmVisible: root.confirmVisible
            confirmTitle:   root.confirmTitle
            confirmBody:    root.confirmBody

            onCallRequested:      root.doCall()
            onMusicRequested:     root.doMusic()
            onTestRequested:      root.doTest()
            onReconnectRequested: root.doReset()
            onFixRequested:       root.doFix()
            onRestoreRequested:   root.doRestoreDefaults()
            onConfirmAccepted:    root.acceptConfirm()
            onConfirmCancelled:   root.cancelConfirm()
        }
    }

    // -------------------------------------------------------------------------
    // Confirmation helpers (an overlay inside the popup, never a blocking dialog)
    // -------------------------------------------------------------------------
    function askConfirm(action, title, body) {
        confirmAction  = action
        confirmTitle   = title
        confirmBody    = body
        confirmVisible = true
    }

    function cancelConfirm() {
        var hadConfirm = confirmVisible && confirmTitle.length > 0
        confirmVisible = false
        confirmAction  = ""
        if (hadConfirm) {
            setMessage("Cancelled.")
        }
    }

    function acceptConfirm() {
        var action = confirmAction
        confirmVisible = false
        confirmAction  = ""
        if (action === "reset-defaults") {
            runResetDefaults()
        }
    }

    // -------------------------------------------------------------------------
    // The single-flight command runner
    // -------------------------------------------------------------------------
    Plasma5.DataSource {
        id: runner
        engine: "executable"
        interval: 0

        onNewData: function (sourceName, data) {
            var p = pending
            // Anything that is not the command we are waiting for is stale.
            if (p === null || sourceName !== p.src) {
                return
            }
            var exitCode  = (data["exit code"]   === undefined) ? -1 : data["exit code"]
            var exitState = (data["exit status"] === undefined) ? 0  : data["exit status"]
            var out       = (data["stdout"]      === undefined) ? "" : data["stdout"]
            var err       = (data["stderr"]      === undefined) ? "" : data["stderr"]

            var done = p.onDone
            var isBg = p.isBackground
            var quiet = p.quiet
            pending = null
            if (!isBg) {
                actionTimeoutTimer.stop()
                if (quiet) {
                    testing = false
                    testCountdownTimer.stop()
                } else {
                    busy = false
                    if (headsetState === "busy") {
                        headsetState = "loading"
                    }
                }
            } else {
                statusTimeoutTimer.stop()
            }
            runner.connectedSources = []

            if (done) {
                done(out, exitCode, exitState, err)
            }
        }
    }

    // A second, tiny exec source polls the sidecar file written by
    // `xm test --live-file`. Plasma's executable data source only reports
    // stdout when a command exits, so polling is what makes the waveform live.
    // We read the whole (tiny) file and ingest only unseen lines, instead of
    // tailing one line: a 120 ms timer would otherwise miss 10 Hz samples.
    Plasma5.DataSource {
        id: liveMeter
        engine: "executable"
        interval: 0

        onNewData: function (sourceName, data) {
            // Ignore a poll that belonged to a previous test.
            if (sourceName !== root.liveMeterSource) {
                return
            }
            root.liveMeterBusy = false
            if (!root.testing || root.liveLevelFile.length === 0) {
                return
            }

            var out = (data["stdout"] === undefined) ? "" : String(data["stdout"])
            if (out.length === 0) {
                return
            }

            // Ignore a final line still being written; it will be complete on
            // the next poll.
            if (out.charAt(out.length - 1) !== "\n") {
                var cut = out.lastIndexOf("\n")
                if (cut < 0) {
                    return
                }
                out = out.slice(0, cut + 1)
            }

            var lines = out.split("\n").filter(function (line) {
                return line.trim().length > 0
            })
            for (var i = root.liveLevelCount; i < lines.length; i++) {
                var value = Number(lines[i])
                if (isFinite(value)) {
                    root.appendLiveLevel(value)
                }
            }
            root.liveLevelCount = Math.max(root.liveLevelCount, lines.length)
        }
    }

    Timer {
        id: liveMeterTimer
        interval: 120
        repeat: true
        running: root.testing && root.liveLevelFile.length > 0
        onTriggered: {
            if (!root.testing) {
                return
            }
            var now = Date.now()
            // Recover if a data-source callback ever goes missing.
            if (root.liveMeterBusy && now - root.liveMeterRequestAt < 1000) {
                return
            }
            root.liveMeterBusy = true
            root.liveMeterRequestAt = now
            root.liveMeterSeq++
            root.liveMeterSource = "cat -- " + root.quotePath(root.liveLevelFile)
                + " #live=" + root.liveMeterSeq
            liveMeter.connectedSources = [root.liveMeterSource]
        }
    }

    function appendLiveLevel(value) {
        var v = Number(value)
        if (!isFinite(v)) {
            return
        }
        v = Math.max(0, Math.min(1, v))
        var next = root.liveLevels.slice()
        next.push(v)
        while (next.length > 50) {
            next.shift()
        }
        root.liveLevels = next
    }

    function startLiveMeter() {
        root.liveLevels = []
        root.liveLevelCount = 0
        root.liveMeterBusy = false
        root.liveMeterRequestAt = 0
        root.liveMeterSeq++
        root.liveMeterSource = ""
        root.liveLevelFile = root.tempDir + "/xm-live-"
            + Date.now() + "-" + Math.floor(Math.random() * 1000000) + ".txt"
    }

    function stopLiveMeter() {
        // Clearing the path stops the timer through its running binding; do
        // not call start()/stop() here or the binding would be destroyed.
        liveMeter.connectedSources = []
        root.liveMeterBusy = false
        root.liveMeterRequestAt = 0
        root.liveMeterSource = ""
        root.liveLevelFile = ""
    }

    Timer {
        id: actionTimeoutTimer
        interval: actionTimeoutMs
        onTriggered: {
            var p = pending
            cancelPending()
            if (p && p.quiet) {
                testing = false
                testCountdownTimer.stop()
                stopLiveMeter()
                setMessage("The mic test timed out. Try Reconnect, then test again.")
            } else {
                if (headsetState === "busy") {
                    headsetState = "loading"
                }
                setMessage("That command timed out. The headset may be asleep.")
                if (p && p.label && p.label.length > 0) {
                    root.notify("xm " + p.label + " timed out", root.message)
                }
            }
            root.refreshInfo()
        }
    }

    Timer {
        id: statusTimeoutTimer
        interval: statusTimeoutMs
        onTriggered: {
            if (pending && pending.isBackground) {
                cancelPending()
                if (!root.busy && !root.testing) {
                    headsetState = "error"
                }
            }
        }
    }

    Timer {
        id: testCountdownTimer
        interval: 1000
        repeat: true
        onTriggered: {
            if (root.testCountdown > 0) {
                root.testCountdown = root.testCountdown - 1
            }
        }
    }

    function cancelPending() {
        if (pending !== null) {
            var wasQuiet = pending.quiet
            runner.connectedSources = []
            pending = null
            if (wasQuiet) {
                testing = false
                testCountdownTimer.stop()
                stopLiveMeter()
            } else {
                busy = false
            }
            actionTimeoutTimer.stop()
            statusTimeoutTimer.stop()
        }
    }

    function quotePath(p) {
        if (p.indexOf(" ") < 0) {
            return p
        }
        return "'" + p.replace(/'/g, "'\\''") + "'"
    }

    /**
     * Run "<xmBin> <argv>" with single flight and a hard timeout.
     * opts.quiet runs without flipping the whole popup into busy state (used by
     * the mic test, which draws its own listening state).
     * Returns true when the command was started, false when one is already
     * running. `onDone(out, code, exitStatus, stderr)` runs at most once.
     */
    function run(argv, label, isBackground, onDone, opts) {
        opts = opts || {}
        if (pending !== null) {
            if (pending.isBackground) {
                cancelPending()
            } else {
                return false
            }
        }
        cmdSeq++
        var src = quotePath(xmBin) + " " + argv + " #seq=" + cmdSeq
        pending = { src: src, onDone: onDone, label: label,
                    isBackground: !!isBackground, quiet: !!opts.quiet }

        if (!isBackground) {
            if (!opts.quiet) {
                busy = true
                headsetState = "busy"
            }
            actionTimeoutTimer.restart()
        } else {
            statusTimeoutTimer.restart()
        }

        runner.connectedSources = [src]
        return true
    }

    function trimEnd(s) {
        return String(s).replace(/[\r\n\s]+$/, "")
    }

    // -------------------------------------------------------------------------
    // Status polling
    //   fast:  status --machine every pollMs, keeps the panel icon current
    //   rich:  info --json only while the popup is open and after an action
    // -------------------------------------------------------------------------
    Timer {
        id: pollTimer
        interval: pollMs
        repeat: true
        running: true
        onTriggered: root.refreshStatus()
    }

    Timer {
        id: infoRefreshTimer
        interval: 12000
        repeat: true
        running: root.expanded
        onTriggered: root.refreshInfo()
    }

    readonly property int pollMs: Math.max(1, cfgPollSec) * 1000

    onExpandedChanged: {
        if (root.expanded) {
            refreshStatus()
            refreshInfo()
        } else {
            // A verdict from a previous meeting is not useful next week.
            testResult = null
            testing = false
            testCountdownTimer.stop()
            stopLiveMeter()
        }
    }

    function refreshStatus() {
        if (busy || testing) {
            return
        }
        run("status --machine", "status", true, function (out, code) {
            var token = trimEnd(out)
            if (code === 0 && (token === "a2dp" || token === "hfp" ||
                               token === "off"  || token === "none" || token === "error")) {
                headsetState = token
                if (token !== "hfp") {
                    testResult = null
                }
                if ((token === "a2dp" || token === "hfp" || token === "off")
                        && root.message.indexOf("timed out") >= 0) {
                    root.message = ""
                }
            } else {
                headsetState = "error"
            }
        })
    }

    function refreshInfo() {
        if (busy || testing) {
            return
        }
        run("info --json", "info", true, function (out, code) {
            if (code !== 0) {
                return
            }
            try {
                var o = JSON.parse(trimEnd(out))
                if (o && typeof o === "object") {
                    root.info = o
                    if (o.state === "a2dp" || o.state === "hfp" || o.state === "off"
                            || o.state === "none" || o.state === "error") {
                        root.headsetState = o.state
                    }
                }
            } catch (e) {
                // Keep the last known good snapshot: a parse error must never
                // blank out a working header.
            }
        })
    }

    // -------------------------------------------------------------------------
    // Actions
    // -------------------------------------------------------------------------
    function doCall()  { switchProfile("call",  "Call profile on: mic + speaker both work.") }
    function doMusic() {
        // A mic verdict belongs to the call profile; never show it in music mode.
        testResult = null
        switchProfile("music", "Music profile on: hi-fi, no mic.")
    }

    function switchProfile(cmd, okMessage) {
        if (!ableToSwitch) {
            return
        }
        setMessage("Switching to " + cmd + "...")
        if (!run(cmd, cmd, false, function (out, code, exitStatus) {
            if (code === 0 && exitStatus === 0) {
                setMessage(okMessage)
                root.notify("xm " + cmd, okMessage)
            } else {
                setMessage("xm " + cmd + " failed (exit " + code + ").")
                root.notify("xm " + cmd + " failed", root.message)
            }
            root.refreshInfo()
        })) {
            setMessage("Still running the previous command.")
        }
    }

    function doTest() {
        if (!connected || !ableToRun) {
            return
        }
        testResult = null

        // A2DP has no microphone at all. Switch first, then record, so a test
        // can never fail just because the headset was left in music mode.
        if (headsetState !== "hfp") {
            setMessage("Switching to Call for the mic test...")
            if (!run("call", "call", false, function (out, code, exitStatus) {
                if (code === 0 && exitStatus === 0) {
                    setMessage("")
                    startMicTest()
                } else {
                    setMessage("Could not switch to Call. Try Reconnect, then test again.")
                    root.refreshInfo()
                }
            })) {
                setMessage("Still running the previous command.")
            }
            return
        }
        startMicTest()
    }

    function startMicTest() {
        if (testing) {
            return
        }
        startLiveMeter()
        testing = true
        testCountdown = 5
        testCountdownTimer.restart()
        setMessage("")

        if (!run("test --json --live-file " + quotePath(liveLevelFile),
                 "test", false, function (out, code) {
            testing = false
            testCountdownTimer.stop()
            stopLiveMeter()

            var r = null
            try {
                r = JSON.parse(trimEnd(out))
            } catch (e) {
                r = null
            }
            if (!r || typeof r !== "object") {
                r = { ok: false, verdict: "error", label: "ERROR",
                      message: "xm test returned an unexpected result", levels: [] }
            }
            root.testResult = r

            var notifyText
            if (r.ok === false) {
                notifyText = "No microphone available - try Reconnect."
            } else if (r.verdict === "live") {
                notifyText = "LIVE - microphone is working (" + Number(r.peak_dbfs).toFixed(1) + " dBFS)"
            } else if (r.verdict === "quiet") {
                notifyText = "QUIET - move closer or raise the headset mic volume"
            } else {
                notifyText = "SILENT - try Reconnect, then test again"
            }
            root.notify("xm test", notifyText)
            root.refreshInfo()
        }, { quiet: true })) {
            testing = false
            testCountdownTimer.stop()
            stopLiveMeter()
            setMessage("Still running the previous command.")
        }
    }

    function doReset() {
        if (!ableToRun) {
            return
        }
        testResult = null
        setMessage("Reconnecting the headset (up to ~60 seconds)...")
        if (!run("reconnect", "reconnect", false, function (out, code) {
            var msg = (code === 0) ? "Headset link reset."
                                   : "xm reconnect failed (exit " + code + ")."
            setMessage(msg)
            root.notify("xm reconnect", msg)
            root.refreshInfo()
        })) {
            setMessage("Still running the previous command.")
        }
    }

    function doFix() {
        if (!ableToRun) {
            return
        }
        testResult = null
        setMessage("Fixing for a meeting (reconnect + Call; usually ~7s, longer if the link is dead)...")
        if (!run("fix", "fix", false, function (out, code) {
            var msg = (code === 0) ? "Ready for the meeting: mic + speaker."
                                   : "xm fix failed (exit " + code + ")."
            setMessage(msg)
            root.notify("xm fix", msg)
            root.refreshInfo()
        })) {
            setMessage("Still running the previous command.")
        }
    }

    function doRestoreDefaults() {
        if (!ableToRun) {
            return
        }
        if (cfgConfirm) {
            askConfirm(
                "reset-defaults",
                "Restore audio defaults?",
                "This removes the xm WirePlumber drop-in and restarts WirePlumber, " +
                "turning automatic A2DP/HFP switching back on.\n\n" +
                "The xm command and this applet stay installed, and you can re-apply " +
                "the fix at any time with:  ./install.sh")
            return
        }
        runResetDefaults()
    }

    function runResetDefaults() {
        setMessage("Restoring WirePlumber defaults...")
        if (!run("defaults-reset", "defaults", false, function (out, code) {
            var msg = (code === 0) ? "WirePlumber defaults restored."
                                   : "Could not restore defaults (exit " + code + ")."
            setMessage(msg)
            if (code === 0) {
                root.notify("xm defaults", msg)
            }
            root.refreshInfo()
        })) {
            setMessage("Still running the previous command.")
        }
    }

    // -------------------------------------------------------------------------
    // Notifications - optional, never fatal
    // -------------------------------------------------------------------------
    function notify(title, body) {
        if (!cfgNotify) {
            return
        }
        try {
            notifier.title = title
            notifier.text  = body
            notifier.sendEvent()
        } catch (e) {
            // Notifications are a bonus; a missing backend must never break an
            // action the user asked for.
        }
    }

    KNotify.Notification {
        id: notifier
        componentName: "xmwidget"
        eventId: "xm"
        iconName: "xmwidget"
    }

    Component.onCompleted: {
        refreshStatus()
        refreshInfo()
    }
}
