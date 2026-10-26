// =============================================================================
//  Offscreen preview harness for HeadsetPopup.qml
// =============================================================================
//  Runs with plain `qml6`, without plasmashell, against the real component.
//  This is how the widget screenshots and every visual iteration are produced.
//
//  Usage (from the repo root):
//    mkdir -p /tmp/opencode/xm-preview
//    QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=KDE \
//      qml6 preview/preview.qml -- --out=/tmp/opencode/xm-preview/sheet.png
//    QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=KDE \
//      qml6 preview/preview.qml -- dark --out=/tmp/opencode/xm-preview/sheet-dark.png
//    QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=KDE \
//      qml6 preview/preview.qml -- --state=hfp --out=/tmp/opencode/xm-preview/hfp.png
//    ... -- --state=a2dp --scale=2 --out=...     # 2x for crisp README assets
//
//  QT_QPA_PLATFORMTHEME=KDE matters: offscreen Qt otherwise has no platform
//  theme and Kirigami.Icon ignores `color`, rendering every icon black even
//  though plasmashell itself looks correct. preview/render-assets.sh sets it.
// =============================================================================

import QtQuick
import QtQuick.Window
import QtQuick.Layouts

import org.kde.kirigami as Kirigami

import "../plasmoid/contents/ui"

Window {
    id: win

    // Resolve arguments before children are created: theme bindings must see
    // the right dark/light value on their first evaluation.
    property bool dark: hasArg("dark")
    property string outPath: argValue("--out=", "/tmp/opencode/xm-preview/sheet.png")
    property string singleState: argValue("--state=", "")
    property real grabScale: Math.max(1, Number(argValue("--scale=", "1")) || 1)

    function argValue(prefix, fallback) {
        var args = Qt.application.arguments
        for (var i = 0; i < args.length; i++) {
            if (String(args[i]).indexOf(prefix) === 0) {
                return String(args[i]).substring(prefix.length)
            }
        }
        return fallback
    }

    function hasArg(name) {
        var args = Qt.application.arguments
        for (var i = 0; i < args.length; i++) {
            if (String(args[i]) === name) return true
        }
        return false
    }

    Component.onCompleted: {
        console.log("preview:", dark ? "dark" : "light", "->", outPath,
                    singleState.length ? ("state=" + singleState) : "sheet",
                    "scale=" + grabScale)
    }

    width: singleState.length > 0 ? 452 : 1340
    height: singleState.length > 0 ? 537 : 1160
    visible: true
    title: "XM Headset preview"

    // Force a theme regardless of the host KDE colour scheme.
    Item {
        id: themeItem
        anchors.fill: parent

        Kirigami.Theme.inherit: false
        Kirigami.Theme.backgroundColor: win.dark ? "#1b1e20" : "#eff0f1"
        Kirigami.Theme.textColor:       win.dark ? "#fcfcfc" : "#232629"
        Kirigami.Theme.highlightColor:  "#3daee9"
        Kirigami.Theme.hoverColor:      win.dark ? "#2a2f33" : "#d6d8da"
        Kirigami.Theme.focusColor:      "#3daee9"
        Kirigami.Theme.alternateBackgroundColor: win.dark ? "#23272b" : "#ffffff"

        Rectangle {
            anchors.fill: parent
            color: Kirigami.Theme.backgroundColor
        }

        GridLayout {
            anchors.fill: parent
            anchors.margins: 16
            columns: win.singleState.length > 0 ? 1 : 3
            columnSpacing: 20
            rowSpacing: 16

            Repeater {
                model: win.singleState.length > 0 ? [win.singleState]
                                                  : ["a2dp", "hfp", "testing",
                                                     "live", "none", "error"]

                ColumnLayout {
                    required property string modelData
                    spacing: 6

                    Rectangle {
                        Layout.preferredWidth: 420
                        Layout.preferredHeight: 505
                        radius: 9
                        color: Kirigami.Theme.backgroundColor
                        border.width: 1
                        border.color: win.dark ? "#394046" : "#c9ccce"

                        HeadsetPopup {
                            anchors.fill: parent
                            state:          win.previewState(modelData)
                            busy:           modelData === "busy"
                            testing:        modelData === "testing"
                            countdown:      3
                            message:        win.previewMessage(modelData)
                            info:           win.previewInfo(modelData)
                            testResult:     win.previewTestResult(modelData)
                            liveLevels:     win.previewLiveLevels(modelData)
                            aboutVisible:   modelData === "about"
                            showText:       true
                        }
                    }

                    Kirigami.Heading {
                        visible: win.singleState.length === 0
                        Layout.alignment: Qt.AlignHCenter
                        text: modelData
                        level: 5
                        opacity: 0.55
                    }
                }
            }
        }
    }

    function previewState(name) {
        switch (name) {
            case "a2dp":
                return "a2dp"
            case "hfp":
            case "testing":
            case "live":
            case "silent":
            case "quiet":
            case "micerror":
            case "notice":
            case "about":
                return "hfp"
            case "none":
                return "none"
            case "error":
                return "error"
            case "busy":
                return "busy"
            default:
                return "a2dp"
        }
    }

    function previewInfo(name) {
        if (name === "none") return {}
        var base = {
            device: "WH-1000XM5",
            mac: "80:99:E7:36:CB:CA",
            battery: 90,
            connected: true,
            wp_config: true
        }
        if (name === "a2dp") {
            base.state = "a2dp"
            base.profile = "a2dp-sink"
            base.codec = "LDAC"
            base.mic = false
        } else if (name === "error") {
            base.state = "error"
            base.profile = null
            base.codec = null
            base.mic = false
            base.connected = false
            base.battery = null
        } else {
            base.state = "hfp"
            base.profile = "headset-head-unit"
            base.codec = "MSBC"
            base.mic = true
        }
        return base
    }

    function previewMessage(name) {
        switch (name) {
            case "busy":   return "Switching to call..."
            case "notice": return "Call profile on: mic + speaker both work."
            case "error":  return "xm could not report a profile."
            default:       return ""
        }
    }

    function previewTestResult(name) {
        if (name === "live") {
            return {
                ok: true, verdict: "live", label: "LIVE",
                peak: 4210, peak_dbfs: -17.8, duration: 5.0,
                levels: wave(1.0, 0.55)
            }
        }
        if (name === "silent") {
            return {
                ok: true, verdict: "silent", label: "SILENT",
                peak: 41, peak_dbfs: -58.1, duration: 5.0,
                levels: wave(0.02, 0.03)
            }
        }
        if (name === "quiet") {
            return {
                ok: true, verdict: "quiet", label: "QUIET",
                peak_dbfs: -48.0, duration: 5.0, levels: wave(0.08, 0.05)
            }
        }
        if (name === "micerror") {
            return {
                ok: false, verdict: "error", label: "NO MIC",
                message: "Switch to Call first, then try again.", levels: []
            }
        }
        return null
    }

    // The real widget receives these at 10 Hz from `xm test --live-file`.
    // Deterministic values keep the README screenshot reproducible.
    function previewLiveLevels(name) {
        if (name === "testing") {
            return wave(1.0, 0.35)
        }
        return []
    }

    function wave(scale, noise) {
        var out = []
        for (var i = 0; i < 50; i++) {
            var envelope = 0.35 + 0.65 * Math.abs(Math.sin(i * 0.37))
            var grain = ((i * 7919) % 13) / 13.0
            out.push(Math.min(1.0, (envelope * 0.55 + grain * noise) * scale))
        }
        return out
    }

    Timer {
        interval: 1200
        running: true
        onTriggered: {
            win.contentItem.grabToImage(function (result) {
                if (result.saveToFile(win.outPath)) {
                    console.log("saved", win.outPath)
                } else {
                    console.log("could not save", win.outPath)
                }
                Qt.quit()
            }, Qt.size(Math.round(win.width * win.grabScale),
                       Math.round(win.height * win.grabScale)))
        }
    }
}
