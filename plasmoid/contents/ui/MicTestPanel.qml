// =============================================================================
//  MicTestPanel - the live microphone instrument
// =============================================================================
//  The hero of the popup. Three states, one panel:
//    idle     "MIC INPUT", READY chip, placeholder bars, Test button
//    testing  live 50-bar waveform, countdown readout and LISTENING chip
//    result   final 50-bar envelope, peak dBFS, verdict chip and icon
//
//  The waveform is real data from `xm test --json` (100 ms windows), so a
//  silently-dead SCO link looks flat instead of pretending to work.
// =============================================================================

import QtQuick
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

Rectangle {
    id: panel

    property bool   testing:        false
    property int    countdown:      5
    property var    result:         null
    property var    liveLevels:     []
    property string profileState:   "none"   // a2dp | hfp | off | ...
    property color  accentColor:    Kirigami.Theme.highlightColor

    signal testRequested()

    readonly property bool hasResult:  result !== null && result !== undefined
    readonly property bool hasError:   hasResult && result.ok === false
    readonly property string verdict:  hasResult ? String(result.verdict || "error") : ""
    readonly property string label:    hasResult ? String(result.label || "") : ""

    readonly property bool isDark: (Kirigami.Theme.textColor.r * 0.299
                                  + Kirigami.Theme.textColor.g * 0.587
                                  + Kirigami.Theme.textColor.b * 0.114) > 0.5
    readonly property color greenColor: isDark ? "#2cd483" : "#178a4c"
    readonly property color amberColor: isDark ? "#e8a33d" : "#a85a00"
    readonly property color redColor:   isDark ? "#e0553e" : "#c92a2a"

    readonly property color verdictColor: {
        switch (verdict) {
            case "live":   return greenColor
            case "quiet":  return amberColor
            case "silent": return redColor
            default:       return hasError ? redColor : accentColor
        }
    }

    readonly property string title: {
        if (testing) return "Listening..."
        if (hasError) return "No microphone available"
        switch (verdict) {
            case "live":   return "Microphone is working"
            case "quiet":  return "Microphone is very quiet"
            case "silent": return "No sound detected"
            default:       return "Microphone check"
        }
    }

    readonly property string subtitle: {
        if (testing) return "Say a few sentences"
        if (hasError) {
            return result.message ? String(result.message)
                                  : "Switch to Call first, then try again."
        }
        switch (verdict) {
            case "live":   return "Call profile · microphone live"
            case "quiet":  return "Move closer, or raise the headset mic volume"
            case "silent": return "Try Reconnect, then test again"
            default:       return profileState === "hfp"
                ? "Speak for 5 seconds to confirm the mic works"
                : "Switches to Call automatically, then tests"
        }
    }

    readonly property string statusIcon: {
        if (hasError) return "dialog-error-symbolic"
        if (testing) return "media-record-symbolic"
        switch (verdict) {
            case "live":   return "audio-input-microphone-symbolic"
            case "quiet":  return "audio-volume-low-symbolic"
            case "silent": return "audio-volume-muted-symbolic"
            default:       return "audio-input-microphone-symbolic"
        }
    }

    readonly property string stateChipText: {
        if (hasError) return "NO MIC"
        if (testing) return "LISTENING"
        switch (verdict) {
            case "live":   return "LIVE"
            case "quiet":  return "QUIET"
            case "silent": return "SILENT"
            default:       return "READY"
        }
    }

    readonly property string peakText: {
        if (testing) return String(countdown)
        if (hasResult && !hasError && !isNaN(Number(result.peak_dbfs)))
            return Number(result.peak_dbfs).toFixed(1).replace("-", "−")
        return "—"
    }

    readonly property string durationText: {
        if (testing || (hasResult && hasError)) return ""
        if (hasResult && !hasError && !isNaN(Number(result.duration)))
            return Number(result.duration).toFixed(1) + " s"
        return "5 s"
    }

    // Placeholder bars, so the panel has a shape before the first test.
    readonly property var idleBars: [0.07, 0.14, 0.09, 0.20, 0.12, 0.06, 0.16, 0.10,
                                     0.05, 0.13, 0.08, 0.15, 0.06, 0.11, 0.07, 0.12,
                                     0.09, 0.18, 0.10, 0.07, 0.14, 0.08, 0.16, 0.11,
                                     0.06, 0.13, 0.09, 0.15]

    // Real levels arrive at 10 Hz from `xm test --live-file`. Pad on the left
    // so a new test scrolls in from the right instead of stretching its bars.
    readonly property var testBars: {
        var source = panel.liveLevels || []
        var out = []
        var pad = Math.max(0, 50 - source.length)
        for (var p = 0; p < pad; p++) {
            out.push(0)
        }
        for (var i = 0; i < source.length; i++) {
            out.push(Number(source[i]) || 0)
        }
        return out.slice(Math.max(0, out.length - 50))
    }

    implicitHeight: Kirigami.Units.gridUnit * 9.8
    radius: Kirigami.Units.smallSpacing * 1.8
    color: Qt.rgba(verdictColor.r, verdictColor.g, verdictColor.b,
                   hasResult || testing ? (isDark ? 0.10 : 0.07) : 0.045)
    border.width: 1
    border.color: Qt.rgba(verdictColor.r, verdictColor.g, verdictColor.b,
                          hasResult || testing ? 0.34 : 0.16)
    Behavior on color        { ColorAnimation { duration: 180 } }
    Behavior on border.color { ColorAnimation { duration: 180 } }

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin:   Kirigami.Units.largeSpacing
        anchors.rightMargin:  Kirigami.Units.largeSpacing
        anchors.topMargin:    Kirigami.Units.smallSpacing * 1.5
        anchors.bottomMargin: Kirigami.Units.smallSpacing * 1.5
        spacing: Kirigami.Units.smallSpacing

        // ---- instrument header -------------------------------------------
        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing * 1.2

            PlasmaComponents3.Label {
                text: "MIC INPUT"
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                font.bold: true
                font.letterSpacing: 1.1
                color: panel.verdictColor
                opacity: 0.9
            }

            Chip {
                text: panel.stateChipText
                tint: panel.verdictColor
                filled: true
            }

            Item { Layout.fillWidth: true }

            PlasmaComponents3.Label {
                visible: text.length > 0
                text: panel.durationText
                font: Kirigami.Theme.smallFont
                color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g,
                               Kirigami.Theme.textColor.b, 0.6)
            }
        }

        // ---- live instrument ---------------------------------------------
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Kirigami.Units.smallSpacing * 1.5

            ColumnLayout {
                Layout.preferredWidth: Kirigami.Units.gridUnit * 4.6
                Layout.fillHeight: true
                spacing: 0

                Item { Layout.fillHeight: true }

                PlasmaComponents3.Label {
                    text: panel.peakText
                    font.bold: true
                    font.pointSize: Kirigami.Theme.defaultFont.pointSize + 12
                    color: panel.peakText === "—"
                        ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g,
                                  Kirigami.Theme.textColor.b, 0.35)
                        : panel.verdictColor
                }

                PlasmaComponents3.Label {
                    text: panel.testing ? "seconds left" : "dBFS peak"
                    font: Kirigami.Theme.smallFont
                    color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g,
                                   Kirigami.Theme.textColor.b, 0.6)
                }

                Item { Layout.fillHeight: true }
            }

            Item {
                id: barsArea
                Layout.fillWidth: true
                Layout.fillHeight: true

                property var levels: panel.testing ? panel.testBars
                                   : (panel.hasResult && !panel.hasError
                                        ? panel.result.levels : panel.idleBars)
                property int barCount: levels ? levels.length : 0
                property real gap: 2
                property real barWidth: barCount > 0
                    ? Math.max(1, (width - (barCount - 1) * gap) / barCount) : 0

                Repeater {
                    model: barsArea.levels

                    Rectangle {
                        required property int index
                        required property var modelData

                        x: index * (barsArea.barWidth + barsArea.gap)
                        width: barsArea.barWidth
                        radius: width / 2
                        height: Math.max(2, barsArea.height * Math.min(1.0,
                                      (Number(modelData) || 0)
                                      * (panel.hasResult || panel.testing ? 1.0 : 1.8)))
                        y: barsArea.height - height
                        color: {
                            if (panel.hasResult && !panel.hasError) {
                                return Qt.rgba(panel.verdictColor.r, panel.verdictColor.g,
                                               panel.verdictColor.b, 0.85)
                            }
                            if (panel.testing) {
                                return Qt.rgba(panel.accentColor.r, panel.accentColor.g,
                                               panel.accentColor.b, 0.85)
                            }
                            return Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g,
                                           Kirigami.Theme.textColor.b,
                                           panel.hasError ? 0.08 : 0.14)
                        }
                        Behavior on height { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
                        Behavior on color  { ColorAnimation  { duration: 180 } }
                    }
                }
            }
        }

        // ---- verdict / action --------------------------------------------
        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            Kirigami.Icon {
                Layout.preferredWidth: 14
                Layout.preferredHeight: 14
                source: panel.statusIcon
                color: panel.verdictColor
                Behavior on color { ColorAnimation { duration: 180 } }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                PlasmaComponents3.Label {
                    Layout.fillWidth: true
                    text: panel.title
                    font.bold: true
                    elide: Text.ElideRight
                }

                PlasmaComponents3.Label {
                    Layout.fillWidth: true
                    text: panel.subtitle
                    font: Kirigami.Theme.smallFont
                    opacity: 0.65
                    elide: Text.ElideRight
                }
            }

            ActionButton {
                id: testButton
                text: panel.hasResult ? "Again" : "Test"
                icon.name: "audio-input-microphone-symbolic"
                primary: true
                accentColor: panel.verdictColor
                Layout.preferredHeight: Kirigami.Units.gridUnit * 2
                enabled: !panel.testing
                onClicked: panel.testRequested()
                PlasmaComponents3.ToolTip {
                    text: panel.hasResult ? "Run the 5 second test again"
                                          : "Record 5 seconds and check the mic (T)"
                    visible: testButton.hovered
                }
            }
        }
    }
}
