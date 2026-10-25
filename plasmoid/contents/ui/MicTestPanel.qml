// =============================================================================
//  MicTestPanel - the "is my microphone actually working?" card
// =============================================================================
//  Three states, one card:
//    idle     "Microphone check" + Test button + faint placeholder bars
//    testing  live 50-bar waveform, countdown chip and progress bar
//    result   50-bar recording waveform + verdict chip + peak dBFS + retry
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
            default:       return hasError ? amberColor : accentColor
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
            case "live":   return "Peak " + Number(result.peak_dbfs).toFixed(1)
                                   + " dBFS over " + Number(result.duration).toFixed(1) + "s"
            case "quiet":  return "Move closer, or raise the headset mic volume"
            case "silent": return "Try Reconnect, then test again"
            default:       return profileState === "hfp"
                ? "Speak for 5 seconds to confirm the mic works"
                : "Switches to Call automatically, then tests"
        }
    }

    // Placeholder bars, so the card has a shape before the first test.
    // Kept intentionally narrow: 28 thin bars read as a waveform, not a bar chart.
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

    implicitHeight: testing ? Kirigami.Units.gridUnit * 8.2
                            : (hasResult ? Kirigami.Units.gridUnit * 8.9
                                         : Kirigami.Units.gridUnit * 6.1)
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

        // ---- header ------------------------------------------------------
        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing * 1.5

            Rectangle {
                Layout.preferredWidth:  Kirigami.Units.gridUnit * 1.9
                Layout.preferredHeight: Kirigami.Units.gridUnit * 1.9
                radius: width / 2
                color: Qt.rgba(verdictColor.r, verdictColor.g, verdictColor.b,
                               testing ? 0.26 : 0.16)
                Behavior on color { ColorAnimation { duration: 180 } }

                Kirigami.Icon {
                    anchors.centerIn: parent
                    width:  Kirigami.Units.iconSizes.smallMedium
                    height: Kirigami.Units.iconSizes.smallMedium
                    source: "audio-input-microphone-symbolic"
                    color: panel.verdictColor
                    Behavior on color { ColorAnimation { duration: 180 } }
                }
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

            Rectangle {
                visible: panel.testing
                Layout.preferredWidth:  Kirigami.Units.gridUnit * 2.2
                Layout.preferredHeight: Kirigami.Units.gridUnit * 1.3
                radius: height / 2
                color: Qt.rgba(panel.verdictColor.r, panel.verdictColor.g,
                               panel.verdictColor.b, 0.20)
                border.width: 1
                border.color: Qt.rgba(panel.verdictColor.r, panel.verdictColor.g,
                                      panel.verdictColor.b, 0.45)

                PlasmaComponents3.Label {
                    anchors.centerIn: parent
                    text: panel.countdown + "s"
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    font.bold: true
                    color: panel.verdictColor
                }
            }

            ActionButton {
                id: testButton
                visible: !panel.testing
                text: panel.hasResult ? "Again" : "Test"
                icon.name: "audio-input-microphone-symbolic"
                primary: true
                accentColor: panel.verdictColor
                enabled: !panel.testing
                onClicked: panel.testRequested()
                PlasmaComponents3.ToolTip {
                    text: panel.hasResult ? "Run the 5 second test again"
                                          : "Record 5 seconds and check the mic (T)"
                    visible: testButton.hovered
                }
            }
        }

        // ---- waveform ----------------------------------------------------
        Item {
            id: barsArea
            Layout.fillWidth: true
            Layout.preferredHeight: Kirigami.Units.gridUnit
                * (panel.testing || panel.hasResult ? 2.3 : 1.4)
            Layout.topMargin: Kirigami.Units.smallSpacing * 0.5

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
                    color: panel.hasResult || panel.testing
                        ? Qt.rgba(panel.verdictColor.r, panel.verdictColor.g,
                                  panel.verdictColor.b, panel.hasError ? 0.35 : 0.85)
                        : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g,
                                  Kirigami.Theme.textColor.b, 0.14)
                    Behavior on height { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
                    Behavior on color  { ColorAnimation  { duration: 180 } }
                }
            }
        }

        // ---- progress / verdict footer ------------------------------------
        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            Rectangle {
                visible: panel.testing
                Layout.fillWidth: true
                Layout.preferredHeight: 3
                radius: 1.5
                color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g,
                               Kirigami.Theme.textColor.b, 0.12)

                Rectangle {
                    height: parent.height
                    radius: parent.height / 2
                    width: parent.width * Math.min(1, Math.max(0, (5 - panel.countdown) / 5))
                    color: panel.verdictColor
                    Behavior on width { NumberAnimation { duration: 900 } }
                }
            }

            Rectangle {
                visible: panel.hasResult && !panel.testing
                Layout.preferredWidth: verdictLabel.implicitWidth
                                      + Kirigami.Units.smallSpacing * 2.4
                Layout.preferredHeight: Kirigami.Units.gridUnit * 1.25
                radius: height / 2
                color: Qt.rgba(panel.verdictColor.r, panel.verdictColor.g,
                               panel.verdictColor.b, 0.18)
                border.width: 1
                border.color: Qt.rgba(panel.verdictColor.r, panel.verdictColor.g,
                                      panel.verdictColor.b, 0.45)

                PlasmaComponents3.Label {
                    id: verdictLabel
                    anchors.centerIn: parent
                    text: panel.hasError ? (panel.label.length ? panel.label : "NO MIC")
                                         : panel.label
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    font.bold: true
                    color: panel.verdictColor
                }
            }

            PlasmaComponents3.Label {
                visible: panel.hasResult && !panel.testing && !panel.hasError
                text: panel.hasResult
                    ? Number(panel.result.duration).toFixed(1) + " s" : ""
                font: Kirigami.Theme.smallFont
                opacity: 0.55
            }

            Item { Layout.fillWidth: true }
        }
    }
}
