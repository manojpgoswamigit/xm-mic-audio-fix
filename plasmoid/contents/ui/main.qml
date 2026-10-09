// =============================================================================
//  XM Headset - Plasma 6 panel applet
// =============================================================================
//  One click on the panel switches the XM Bluetooth headset between:
//
//      Call   -> HFP/mSBC  : microphone AND speaker work (before a meeting)
//      Music  -> A2DP/LDAC : hi-fi output, no mic        (after a meeting)
//
//  plus three helpers (Test / Reset / Fix), a live profile indicator and a
//  safe "restore audio defaults" escape hatch.
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
// =============================================================================

import QtQuick
import QtQuick.Layouts
import Qt.labs.platform as Labs

import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.extras as PlasmaExtras
import org.kde.plasma.plasma5support as Plasma5
import org.kde.notification as KNotify

PlasmoidItem {
    id: root

    // -------------------------------------------------------------------------
    // Configured behaviour (see contents/config/main.xml)
    // -------------------------------------------------------------------------
    readonly property string configuredPath: readCfg("xmPath", "")
    readonly property int    cfgPollSec:     parseInt(readCfg("pollInterval", 2))
    readonly property bool   cfgShowText:    readCfg("showText", true) === true
                                              || readCfg("showText", true) === "true"
    readonly property bool   cfgConfirm:     readCfg("confirmReset", true) === true
                                              || readCfg("confirmReset", true) === "true"
    readonly property bool   cfgNotify:      readCfg("notifications", true) === true
                                              || readCfg("notifications", true) === "true"

    function readCfg(key, fallback) {
        if (!Plasmoid || !Plasmoid.configuration) {
            return fallback
        }
        var v = Plasmoid.configuration[key]
        return (v === undefined || v === null) ? fallback : v
    }

    // Resolved without relying on the shell expanding a leading "~": the
    // Plasma job runner does not guarantee that. If HOME ever resolves empty
    // the applet simply lands in its error state and the path can be set in
    // the applet configuration.
    function pathFromUrl(u) {
        // StandardPaths returns a file:// URL in Qt6; strip the scheme.
        return String(u).replace(/^file:\/\//, "")
    }

    readonly property string homeDir: pathFromUrl(
        Labs.StandardPaths.writableLocation(Labs.StandardPaths.HomeLocation))

    readonly property string xmBin: configuredPath.length > 0
        ? configuredPath
        : homeDir + "/.local/bin/xm"

    // -------------------------------------------------------------------------
    // State
    // -------------------------------------------------------------------------
    // headsetState: loading | a2dp | hfp | none | error | busy
    property string headsetState: "loading"
    property bool   busy:         false
    property string message:      ""
    property bool   aboutVisible: false

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
        onTriggered: {
            root.message = ""
        }
    }

    // one command at a time
    property var pending: null
    property int cmdSeq:  0

    readonly property int actionTimeoutMs: 30000
    readonly property int statusTimeoutMs: 4000

    // Adaptive theme detection: text luminance > 0.5 means text is light, so background is dark.
    readonly property bool isDark: (Kirigami.Theme.textColor.r * 0.299 + Kirigami.Theme.textColor.g * 0.587 + Kirigami.Theme.textColor.b * 0.114) > 0.5

    // High-contrast, theme-aware semantic colors for panel and root elements
    readonly property color colorA2dp: Kirigami.Theme.highlightColor
    readonly property color colorHfp:  isDark ? "#2cd483" : "#178a4c"
    readonly property color colorOff:  isDark ? "#8d9296" : "#59636e"
    readonly property color colorBusy: isDark ? "#e8a33d" : "#b25e00"
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

    readonly property string iconSource: "xmwidget"

    readonly property bool ableToRun:    !busy
    readonly property bool ableToSwitch: ableToRun && (headsetState === "a2dp" || headsetState === "hfp" || headsetState === "off")

    readonly property string statusLine: {
        switch (headsetState) {
            case "a2dp":  return "Connected - A2DP: hi-fi music, no mic"
            case "hfp":   return "Connected - HFP: mic + speaker, voice grade"
            case "off":   return "Connected - standby (click Call or Music)"
            case "busy":  return "Working..."
            case "none":  return "No Bluetooth headset found"
            case "error": return "xm could not report a profile"
            default:      return "Checking..."
        }
    }

    readonly property string tooltipSub: {
        switch (headsetState) {
            case "a2dp":  return "Music profile (A2DP) - no microphone"
            case "hfp":   return "Call profile (HFP) - mic + speaker"
            case "off":   return "Connected - standby (click Call or Music)"
            case "busy":  return "Working..."
            case "none":  return "No Bluetooth headset found"
            case "error": return "xm could not report a profile"
            default:      return "Checking..."
        }
    }

    readonly property string aboutText:
        "One-click profile switching for the XM Bluetooth headset.\n\n" +
        "Call   ->  HFP/mSBC   microphone + speaker  (before a meeting)\n" +
        "Music  ->  A2DP/LDAC  hi-fi output, no mic  (after a meeting)\n\n" +
        "Every button just runs the `xm` command; this applet never touches\n" +
        "the audio stack itself.\n\n" +
        "To take the whole thing off your system:\n" +
        "    ~/xm-mic-audio-fix/rollback.sh\n\n" +
        "That removes the applet, the xm command and the WirePlumber drop-in,\n" +
        "restoring automatic A2DP/HFP switching. Nothing is left behind."

    // -------------------------------------------------------------------------
    // Plasmoid identity and tooltip
    // -------------------------------------------------------------------------
    toolTipMainText: "XM Headset"
    toolTipSubText:  tooltipSub

    // -------------------------------------------------------------------------
    // Compact representation: one tinted icon, no text
    // -------------------------------------------------------------------------
    compactRepresentation: Item {
        id: compactHolder

        Kirigami.Icon {
            id: compactIcon
            objectName: "compactIcon"
            anchors.centerIn: parent
            width:  Math.min(parent.width, parent.height) * 0.85
            height: width
            source: "audio-headset-symbolic"
            color:  root.stateColor
            opacity: root.busy ? 0.45 : 1.0
            Behavior on opacity { NumberAnimation { duration: 220 } }
            Behavior on color { ColorAnimation { duration: 200 } }
        }
    }

    // -------------------------------------------------------------------------
    // Full representation
    // -------------------------------------------------------------------------
    fullRepresentation: PlasmaExtras.Representation {
        id: popup

        Layout.minimumWidth:  Kirigami.Units.gridUnit * 19
        Layout.preferredWidth: Kirigami.Units.gridUnit * 20
        Layout.minimumHeight: Kirigami.Units.gridUnit * 18
        Layout.preferredHeight: Kirigami.Units.gridUnit * 19

        // The popup draws as a "View", so children get the right palette.
        Kirigami.Theme.colorSet: Kirigami.Theme.View

        // Scoped theme awareness for the popup surface
        readonly property bool popupIsDark: (Kirigami.Theme.textColor.r * 0.299 + Kirigami.Theme.textColor.g * 0.587 + Kirigami.Theme.textColor.b * 0.114) > 0.5
        readonly property color popupColorA2dp: Kirigami.Theme.highlightColor
        readonly property color popupColorHfp:  popupIsDark ? "#2cd483" : "#178a4c"
        readonly property color popupColorOff:  popupIsDark ? "#8d9296" : "#59636e"
        readonly property color popupColorBusy: popupIsDark ? "#e8a33d" : "#b25e00"
        readonly property color popupColorErr:  popupIsDark ? "#e0553e" : "#c92a2a"

        readonly property color popupStateColor: {
            switch (root.headsetState) {
                case "a2dp":  return popupColorA2dp
                case "hfp":   return popupColorHfp
                case "off":   return popupColorBusy
                case "busy":  return popupColorBusy
                case "error": return popupColorErr
                case "none":  return popupColorOff
                default:      return popupColorOff
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.largeSpacing
            spacing: Kirigami.Units.largeSpacing

            // ---- header ----
            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing * 2

                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    Layout.preferredWidth:  Kirigami.Units.iconSizes.medium
                    Layout.preferredHeight: Kirigami.Units.iconSizes.medium
                    radius: width / 2
                    color: Qt.rgba(popup.popupStateColor.r, popup.popupStateColor.g, popup.popupStateColor.b, popup.popupIsDark ? 0.18 : 0.12)
                    border.color: Qt.rgba(popup.popupStateColor.r, popup.popupStateColor.g, popup.popupStateColor.b, popup.popupIsDark ? 0.30 : 0.25)
                    border.width: 1
                    Behavior on color { ColorAnimation { duration: 200 } }
                    Behavior on border.color { ColorAnimation { duration: 200 } }

                    Kirigami.Icon {
                        anchors.centerIn: parent
                        width:  Kirigami.Units.iconSizes.small
                        height: Kirigami.Units.iconSizes.small
                        source: "audio-headset-symbolic"
                        color:  popup.popupStateColor
                        Behavior on color { ColorAnimation { duration: 200 } }
                    }
                }

                PlasmaComponents3.Label {
                    Layout.fillWidth: true
                    text: "XM Headset"
                    font.bold: true
                    font.pointSize: Kirigami.Theme.defaultFont.pointSize + 1
                    elide: Text.ElideRight
                }

                PlasmaComponents3.ToolButton {
                    objectName: "aboutButton"
                    icon.name: "help-about-symbolic"
                    display:  PlasmaComponents3.AbstractButton.IconOnly
                    PlasmaComponents3.ToolTip { text: "About this applet" }
                    onClicked: root.aboutVisible = true
                }
            }

            // ---- status pill ----
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: Kirigami.Units.gridUnit * 1.8
                visible: cfgShowText
                radius: Kirigami.Units.smallSpacing * 1.5
                color: Qt.rgba(popup.popupStateColor.r, popup.popupStateColor.g, popup.popupStateColor.b, popup.popupIsDark ? 0.12 : 0.08)
                border.color: Qt.rgba(popup.popupStateColor.r, popup.popupStateColor.g, popup.popupStateColor.b, popup.popupIsDark ? 0.28 : 0.35)
                border.width: 1
                Behavior on color { ColorAnimation { duration: 200 } }
                Behavior on border.color { ColorAnimation { duration: 200 } }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Kirigami.Units.largeSpacing
                    anchors.rightMargin: Kirigami.Units.largeSpacing
                    spacing: Kirigami.Units.smallSpacing * 2

                    Rectangle {
                        Layout.alignment: Qt.AlignVCenter
                        width: 8
                        height: 8
                        radius: 4
                        color: popup.popupStateColor
                        Behavior on color { ColorAnimation { duration: 200 } }
                    }

                    PlasmaComponents3.Label {
                        Layout.fillWidth: true
                        text: root.statusLine
                        elide: Text.ElideRight
                        font: Kirigami.Theme.smallFont
                    }
                }
            }

            // ---- transient result message ----
            Rectangle {
                Layout.fillWidth: true
                visible: cfgShowText && root.message.length > 0
                Layout.preferredHeight: messageLabel.implicitHeight + Kirigami.Units.smallSpacing * 2
                radius: Kirigami.Units.smallSpacing
                color: Kirigami.Theme.alternateBackgroundColor
                border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, popup.popupIsDark ? 0.12 : 0.15)
                border.width: 1

                PlasmaComponents3.Label {
                    id: messageLabel
                    anchors.fill: parent
                    anchors.margins: Kirigami.Units.smallSpacing
                    text: root.message
                    wrapMode: Text.WordWrap
                    font: Kirigami.Theme.smallFont
                    opacity: 0.9
                    horizontalAlignment: Text.AlignHCenter
                }
            }

            // ---- primary actions ----
            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing * 2

                PlasmaComponents3.Button {
                    id: callButton
                    objectName: "callButton"
                    Layout.fillWidth: true
                    Layout.preferredHeight: Kirigami.Units.gridUnit * 5.2
                    enabled: root.ableToSwitch
                    onClicked: root.doCall()

                    PlasmaComponents3.ToolTip {
                        visible: callButton.hovered
                        text: "xm call - switch to HFP so the mic works"
                    }

                    background: Rectangle {
                        radius: Kirigami.Units.smallSpacing * 2
                        color: {
                            if (root.headsetState === "hfp") {
                                return Qt.rgba(popup.popupColorHfp.r, popup.popupColorHfp.g, popup.popupColorHfp.b, callButton.down ? 0.25 : (popup.popupIsDark ? 0.16 : 0.12))
                            }
                            if (callButton.hovered) {
                                return Kirigami.Theme.hoverColor
                            }
                            return Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, popup.popupIsDark ? 0.05 : 0.04)
                        }
                        border.color: {
                            if (root.headsetState === "hfp") {
                                return popup.popupColorHfp
                            }
                            if (callButton.hovered) {
                                return Kirigami.Theme.focusColor
                            }
                            return Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, popup.popupIsDark ? 0.12 : 0.14)
                        }
                        border.width: (root.headsetState === "hfp") ? 2 : 1
                        opacity: callButton.enabled ? 1.0 : 0.4
                        Behavior on color { ColorAnimation { duration: 150 } }
                        Behavior on border.color { ColorAnimation { duration: 150 } }
                    }

                    contentItem: ColumnLayout {
                        anchors.centerIn: parent
                        spacing: Kirigami.Units.smallSpacing

                        Kirigami.Icon {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.preferredWidth:  Kirigami.Units.iconSizes.medium
                            Layout.preferredHeight: Kirigami.Units.iconSizes.medium
                            source: "audio-headset-symbolic"
                            color: (root.headsetState === "hfp") ? popup.popupColorHfp : (callButton.enabled ? Kirigami.Theme.textColor : popup.popupColorOff)
                        }

                        PlasmaComponents3.Label {
                            Layout.alignment: Qt.AlignHCenter
                            text: "Call"
                            font.bold: true
                            color: (root.headsetState === "hfp") ? popup.popupColorHfp : Kirigami.Theme.textColor
                        }

                        PlasmaComponents3.Label {
                            Layout.alignment: Qt.AlignHCenter
                            text: "mic + speaker"
                            font: Kirigami.Theme.smallFont
                            opacity: (root.headsetState === "hfp") ? 0.9 : 0.65
                            color: Kirigami.Theme.textColor
                        }
                    }
                }

                PlasmaComponents3.Button {
                    id: musicButton
                    objectName: "musicButton"
                    Layout.fillWidth: true
                    Layout.preferredHeight: Kirigami.Units.gridUnit * 5.2
                    enabled: root.ableToSwitch
                    onClicked: root.doMusic()

                    PlasmaComponents3.ToolTip {
                        visible: musicButton.hovered
                        text: "xm music - switch back to hi-fi A2DP"
                    }

                    background: Rectangle {
                        radius: Kirigami.Units.smallSpacing * 2
                        color: {
                            if (root.headsetState === "a2dp") {
                                return Qt.rgba(popup.popupColorA2dp.r, popup.popupColorA2dp.g, popup.popupColorA2dp.b, musicButton.down ? 0.25 : (popup.popupIsDark ? 0.16 : 0.12))
                            }
                            if (musicButton.hovered) {
                                return Kirigami.Theme.hoverColor
                            }
                            return Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, popup.popupIsDark ? 0.05 : 0.04)
                        }
                        border.color: {
                            if (root.headsetState === "a2dp") {
                                return popup.popupColorA2dp
                            }
                            if (musicButton.hovered) {
                                return Kirigami.Theme.focusColor
                            }
                            return Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, popup.popupIsDark ? 0.12 : 0.14)
                        }
                        border.width: (root.headsetState === "a2dp") ? 2 : 1
                        opacity: musicButton.enabled ? 1.0 : 0.4
                        Behavior on color { ColorAnimation { duration: 150 } }
                        Behavior on border.color { ColorAnimation { duration: 150 } }
                    }

                    contentItem: ColumnLayout {
                        anchors.centerIn: parent
                        spacing: Kirigami.Units.smallSpacing

                        Kirigami.Icon {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.preferredWidth:  Kirigami.Units.iconSizes.medium
                            Layout.preferredHeight: Kirigami.Units.iconSizes.medium
                            source: "audio-speakers-symbolic"
                            color: (root.headsetState === "a2dp") ? popup.popupColorA2dp : (musicButton.enabled ? Kirigami.Theme.textColor : popup.popupColorOff)
                        }

                        PlasmaComponents3.Label {
                            Layout.alignment: Qt.AlignHCenter
                            text: "Music"
                            font.bold: true
                            color: (root.headsetState === "a2dp") ? popup.popupColorA2dp : Kirigami.Theme.textColor
                        }

                        PlasmaComponents3.Label {
                            Layout.alignment: Qt.AlignHCenter
                            text: "hi-fi, no mic"
                            font: Kirigami.Theme.smallFont
                            opacity: (root.headsetState === "a2dp") ? 0.9 : 0.65
                            color: Kirigami.Theme.textColor
                        }
                    }
                }
            }

            // ---- helpers ----
            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing * 1.5

                PlasmaComponents3.Button {
                    id: testButton
                    objectName: "testButton"
                    Layout.fillWidth: true
                    text: "Test mic"
                    icon.name: "audio-input-microphone-symbolic"
                    enabled: root.ableToRun
                    onClicked: root.doTest()
                }

                PlasmaComponents3.Button {
                    id: resetButton
                    objectName: "resetButton"
                    Layout.fillWidth: true
                    text: "Reset link"
                    icon.name: "view-refresh-symbolic"
                    enabled: root.ableToRun
                    onClicked: root.doReset()
                }

                PlasmaComponents3.Button {
                    id: fixButton
                    objectName: "fixButton"
                    Layout.fillWidth: true
                    text: "Fix"
                    icon.name: "tools-symbolic"
                    enabled: root.ableToRun
                    onClicked: root.doFix()
                }
            }

            PlasmaComponents3.BusyIndicator {
                Layout.alignment: Qt.AlignHCenter
                visible: root.busy
                running: root.busy
                Layout.preferredHeight: root.busy ? Kirigami.Units.gridUnit * 1.5 : 0
            }

            Item { Layout.fillHeight: true }

            Kirigami.Separator {
                Layout.fillWidth: true
                opacity: 0.45
            }

            // ---- footer ----
            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing * 2

                PlasmaComponents3.ToolButton {
                    id: defaultsButton
                    objectName: "defaultsButton"
                    text: "Restore audio defaults"
                    icon.name: "edit-undo-symbolic"
                    display: PlasmaComponents3.AbstractButton.TextBesideIcon
                    enabled: root.ableToRun
                    onClicked: root.doRestoreDefaults()
                }

                Item { Layout.fillWidth: true }

                PlasmaComponents3.Label {
                    text: "via xm"
                    opacity: 0.5
                    font: Kirigami.Theme.smallFont
                }
            }
        }

        // ---- overlay: About and confirmations ----
        Rectangle {
            id: overlay
            anchors.fill: parent
            visible: root.aboutVisible || root.confirmVisible
            color: Kirigami.Theme.backgroundColor
            border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, popup.popupIsDark ? 0.16 : 0.20)
            border.width: 1
            radius: Kirigami.Units.smallSpacing * 1.5
            clip: true
            z: 99

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Kirigami.Units.largeSpacing
                spacing: Kirigami.Units.smallSpacing * 1.5

                // ---- modal header ----
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing * 2

                    Rectangle {
                        Layout.alignment: Qt.AlignVCenter
                        Layout.preferredWidth:  Kirigami.Units.iconSizes.medium
                        Layout.preferredHeight: Kirigami.Units.iconSizes.medium
                        radius: width / 2
                        color: Qt.rgba(
                            (root.aboutVisible ? popup.popupColorA2dp : popup.popupColorBusy).r,
                            (root.aboutVisible ? popup.popupColorA2dp : popup.popupColorBusy).g,
                            (root.aboutVisible ? popup.popupColorA2dp : popup.popupColorBusy).b,
                            popup.popupIsDark ? 0.18 : 0.12)
                        border.color: Qt.rgba(
                            (root.aboutVisible ? popup.popupColorA2dp : popup.popupColorBusy).r,
                            (root.aboutVisible ? popup.popupColorA2dp : popup.popupColorBusy).g,
                            (root.aboutVisible ? popup.popupColorA2dp : popup.popupColorBusy).b,
                            popup.popupIsDark ? 0.30 : 0.25)
                        border.width: 1

                        Kirigami.Icon {
                            anchors.centerIn: parent
                            width:  Kirigami.Units.iconSizes.small
                            height: Kirigami.Units.iconSizes.small
                            source: root.aboutVisible ? "audio-headset-symbolic" : "dialog-warning-symbolic"
                            color:  root.aboutVisible ? popup.popupColorA2dp : popup.popupColorBusy
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1

                        PlasmaComponents3.Label {
                            Layout.fillWidth: true
                            font.bold: true
                            font.pointSize: Kirigami.Theme.defaultFont.pointSize + 1
                            text: root.aboutVisible ? "About XM Headset" : root.confirmTitle
                            elide: Text.ElideRight
                        }

                        PlasmaComponents3.Label {
                            Layout.fillWidth: true
                            text: root.aboutVisible ? "Profile Manager for PipeWire" : "Action confirmation"
                            font: Kirigami.Theme.smallFont
                            opacity: 0.6
                            elide: Text.ElideRight
                        }
                    }

                    PlasmaComponents3.ToolButton {
                        icon.name: "dialog-close-symbolic"
                        display:  PlasmaComponents3.AbstractButton.IconOnly
                        PlasmaComponents3.ToolTip { text: "Close" }
                        onClicked: {
                            if (root.aboutVisible) {
                                root.aboutVisible = false
                            } else {
                                root.cancelConfirm()
                            }
                        }
                    }
                }

                Kirigami.Separator {
                    Layout.fillWidth: true
                    opacity: 0.35
                }

                // ---- scrollable content ----
                PlasmaComponents3.ScrollView {
                    id: overlayScroll
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    PlasmaComponents3.ScrollBar.horizontal.policy: PlasmaComponents3.ScrollBar.AlwaysOff

                    ColumnLayout {
                        width: overlayScroll.availableWidth
                        spacing: Kirigami.Units.smallSpacing * 1.5

                        // About View
                        ColumnLayout {
                            Layout.fillWidth: true
                            visible: root.aboutVisible
                            spacing: Kirigami.Units.smallSpacing * 1.5

                            PlasmaComponents3.Label {
                                Layout.fillWidth: true
                                text: "One-click profile switcher for Sony WH-1000XM headsets under PipeWire."
                                wrapMode: Text.WordWrap
                                opacity: 0.9
                            }

                            // Call mini-card
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: aboutCallRow.implicitHeight + Kirigami.Units.smallSpacing * 2
                                radius: Kirigami.Units.smallSpacing
                                color: Qt.rgba(popup.popupColorHfp.r, popup.popupColorHfp.g, popup.popupColorHfp.b, popup.popupIsDark ? 0.12 : 0.08)
                                border.color: Qt.rgba(popup.popupColorHfp.r, popup.popupColorHfp.g, popup.popupColorHfp.b, 0.3)
                                border.width: 1

                                RowLayout {
                                    id: aboutCallRow
                                    anchors.fill: parent
                                    anchors.leftMargin: Kirigami.Units.smallSpacing * 1.5
                                    anchors.rightMargin: Kirigami.Units.smallSpacing * 1.5
                                    spacing: Kirigami.Units.smallSpacing * 1.5

                                    Kirigami.Icon {
                                        source: "audio-headset-symbolic"
                                        Layout.preferredWidth: Kirigami.Units.iconSizes.small
                                        Layout.preferredHeight: Kirigami.Units.iconSizes.small
                                        color: popup.popupColorHfp
                                    }

                                    PlasmaComponents3.Label {
                                        text: "Call"
                                        font.bold: true
                                        color: popup.popupColorHfp
                                    }

                                    PlasmaComponents3.Label {
                                        Layout.fillWidth: true
                                        text: "HFP / mSBC: mic + speaker for meetings"
                                        elide: Text.ElideRight
                                        font: Kirigami.Theme.smallFont
                                    }
                                }
                            }

                            // Music mini-card
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: aboutMusicRow.implicitHeight + Kirigami.Units.smallSpacing * 2
                                radius: Kirigami.Units.smallSpacing
                                color: Qt.rgba(popup.popupColorA2dp.r, popup.popupColorA2dp.g, popup.popupColorA2dp.b, popup.popupIsDark ? 0.12 : 0.08)
                                border.color: Qt.rgba(popup.popupColorA2dp.r, popup.popupColorA2dp.g, popup.popupColorA2dp.b, 0.3)
                                border.width: 1

                                RowLayout {
                                    id: aboutMusicRow
                                    anchors.fill: parent
                                    anchors.leftMargin: Kirigami.Units.smallSpacing * 1.5
                                    anchors.rightMargin: Kirigami.Units.smallSpacing * 1.5
                                    spacing: Kirigami.Units.smallSpacing * 1.5

                                    Kirigami.Icon {
                                        source: "audio-speakers-symbolic"
                                        Layout.preferredWidth: Kirigami.Units.iconSizes.small
                                        Layout.preferredHeight: Kirigami.Units.iconSizes.small
                                        color: popup.popupColorA2dp
                                    }

                                    PlasmaComponents3.Label {
                                        text: "Music"
                                        font.bold: true
                                        color: popup.popupColorA2dp
                                    }

                                    PlasmaComponents3.Label {
                                        Layout.fillWidth: true
                                        text: "A2DP / LDAC: hi-fi output, no mic"
                                        elide: Text.ElideRight
                                        font: Kirigami.Theme.smallFont
                                    }
                                }
                            }

                            // Rollback note
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: rollbackBox.implicitHeight + Kirigami.Units.smallSpacing * 2
                                radius: Kirigami.Units.smallSpacing
                                color: Kirigami.Theme.alternateBackgroundColor
                                border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, popup.popupIsDark ? 0.12 : 0.15)
                                border.width: 1

                                ColumnLayout {
                                    id: rollbackBox
                                    anchors.fill: parent
                                    anchors.margins: Kirigami.Units.smallSpacing
                                    spacing: 2

                                    PlasmaComponents3.Label {
                                        text: "To restore defaults or uninstall:"
                                        font: Kirigami.Theme.smallFont
                                        opacity: 0.7
                                    }

                                    PlasmaComponents3.Label {
                                        text: "~/xm-mic-audio-fix/rollback.sh"
                                        font.bold: true
                                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                                    }
                                }
                            }
                        }

                        // Confirmation View
                        ColumnLayout {
                            Layout.fillWidth: true
                            visible: root.confirmVisible
                            spacing: Kirigami.Units.smallSpacing * 1.5

                            PlasmaComponents3.Label {
                                Layout.fillWidth: true
                                text: root.confirmBody
                                wrapMode: Text.WordWrap
                                opacity: 0.9
                            }
                        }
                    }
                }

                Kirigami.Separator {
                    Layout.fillWidth: true
                    opacity: 0.35
                }

                // ---- footer buttons ----
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing * 2

                    Item { Layout.fillWidth: true }

                    PlasmaComponents3.Button {
                        visible: !root.aboutVisible
                        text: "Cancel"
                        onClicked: root.cancelConfirm()
                    }

                    PlasmaComponents3.Button {
                        text: root.aboutVisible ? "Done" : "Do it"
                        font.bold: true
                        onClicked: {
                            if (root.aboutVisible) {
                                root.aboutVisible = false
                            } else {
                                root.acceptConfirm()
                            }
                        }
                    }
                }
            }
        }
    }

    // -------------------------------------------------------------------------
    // Confirmation state (an overlay inside the popup, never a blocking dialog)
    // -------------------------------------------------------------------------
    property bool   confirmVisible: false
    property string confirmTitle:   ""
    property string confirmBody:    ""
    property string confirmAction:  ""

    function askConfirm(action, title, body) {
        confirmAction = action
        confirmTitle  = title
        confirmBody   = body
        confirmVisible = true
    }

    function cancelConfirm() {
        var hadConfirm = confirmVisible && confirmTitle.length > 0
        confirmVisible = false
        aboutVisible   = false
        confirmAction  = ""
        if (hadConfirm) {
            setMessage("Cancelled.")
        }
    }

    function acceptConfirm() {
        var action = confirmAction
        confirmVisible = false
        aboutVisible   = false
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
            pending = null
            if (!isBg) {
                busy = false
                actionTimeoutTimer.stop()
                if (headsetState === "busy") {
                    headsetState = "loading"
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

    Timer {
        id: actionTimeoutTimer
        interval: actionTimeoutMs
        onTriggered: {
            var p = pending
            cancelPending()
            if (headsetState === "busy") {
                headsetState = "loading"
            }
            setMessage("That command timed out. The headset may be asleep.")
            if (p && p.label && p.label.length > 0) {
                root.notify("xm " + p.label + " timed out", root.message)
            }
            root.refreshStatus()
        }
    }

    Timer {
        id: statusTimeoutTimer
        interval: statusTimeoutMs
        onTriggered: {
            if (pending && pending.isBackground) {
                cancelPending()
                headsetState = "error"
            }
        }
    }

    function cancelPending() {
        if (pending !== null) {
            runner.connectedSources = []
            pending = null
            busy = false
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
     * Returns true when the command was started, false when one is already
     * running. `onDone(out, code, exitStatus, stderr)` runs at most once.
     */
    function run(argv, label, isBackground, onDone) {
        if (pending !== null) {
            if (pending.isBackground) {
                // Cancel background status poll in favor of user action or new request
                cancelPending()
            } else {
                // User action already in flight
                return false
            }
        }
        cmdSeq++
        var src = quotePath(xmBin) + " " + argv + " #seq=" + cmdSeq
        pending = { src: src, onDone: onDone, label: label, isBackground: !!isBackground }

        if (!isBackground) {
            busy = true
            headsetState = "busy"
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
    // -------------------------------------------------------------------------
    Timer {
        id: pollTimer
        interval: pollMs
        repeat: true
        running: true
        onTriggered: root.refreshStatus()
    }

    readonly property int pollMs: Math.max(1, cfgPollSec) * 1000

    function refreshStatus() {
        if (busy) {
            return
        }
        run("status --machine", "status", true, function (out, code) {
            var token = trimEnd(out)
            if (code === 0 && (token === "a2dp" || token === "hfp" ||
                               token === "off"  || token === "none" || token === "error")) {
                headsetState = token
                if ((token === "a2dp" || token === "hfp" || token === "off") && root.message.indexOf("timed out") >= 0) {
                    root.message = ""
                }
            } else {
                headsetState = "error"
            }
        })
    }

    // -------------------------------------------------------------------------
    // Actions
    // -------------------------------------------------------------------------
    function doCall()  { switchProfile("call",  "Call profile on: mic + speaker both work.") }
    function doMusic() { switchProfile("music", "Music profile on: hi-fi, no mic.") }

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
            root.refreshStatus()
        })) {
            setMessage("Still running the previous command.")
        }
    }

    function doTest() {
        if (!ableToRun) {
            return
        }
        setMessage("Testing the mic - speak now (5 seconds)...")
        if (!run("test", "test", false, function (out, code) {
            var verdict = "Mic test finished."
            var lines = trimEnd(out).split("\n")
            for (var i = lines.length - 1; i >= 0; i--) {
                if (lines[i].indexOf("VERDICT:") === 0) {
                    verdict = lines[i].replace("VERDICT: ", "")
                    break
                }
            }
            setMessage(verdict)
            root.notify("xm test", verdict)
            root.refreshStatus()
        })) {
            setMessage("Still running the previous command.")
        }
    }

    function doReset() {
        if (!ableToRun) {
            return
        }
        setMessage("Resetting the headset link (about 6 seconds)...")
        if (!run("reset", "reset", false, function (out, code) {
            var msg = (code === 0) ? "Headset link reset."
                                   : "xm reset failed (exit " + code + ")."
            setMessage(msg)
            root.notify("xm reset", msg)
            root.refreshStatus()
        })) {
            setMessage("Still running the previous command.")
        }
    }

    function doFix() {
        if (!ableToRun) {
            return
        }
        setMessage("Fixing for a meeting (reset + call, about 6 seconds)...")
        if (!run("fix", "fix", false, function (out, code) {
            var msg = (code === 0) ? "Ready for the meeting: mic + speaker."
                                   : "xm fix failed (exit " + code + ")."
            setMessage(msg)
            root.notify("xm fix", msg)
            root.refreshStatus()
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
            root.refreshStatus()
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
    }
}
