// =============================================================================
//  HeadsetPopup - the whole XM Headset popup, as a pure view
// =============================================================================
//  Properties in, signals out. main.qml owns the runner and state; this file
//  only draws. That split is what lets preview/preview.qml render every state
//  offscreen for screenshots without starting plasmashell.
//
//  Layout
//    header      device name, connection state, codec/battery chips
//    message     transient result of the last action
//    recovery    only when the headset is absent or unreadable
//    cards       Call / Music
//    mic test    idle, listening or waveform + verdict
//    helpers     Reconnect, Fix for meeting
//    footer      Restore audio defaults
//
//  Overlays (About, confirmation) live inside the popup, never as blocking
//  dialogs, so the applet can never hang plasmashell.
// =============================================================================

import QtQuick
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

Item {
    id: root

    // Inherit the host popup/applet palette immediately at component creation.
    Kirigami.Theme.inherit: true

    // ---- state -----------------------------------------------------------
    property string state:        "loading"   // loading|a2dp|hfp|off|none|error|busy
    property string connectionAction: ""
    property bool   busy:         false
    property bool   testing:      false
    property int    countdown:    5
    property string message:      ""
    property var    info:         ({})
    property var    testResult:   null
    property var    liveLevels:   []
    property bool   showText:     true
    property bool   confirmVisible: false
    property string confirmTitle:  ""
    property string confirmBody:   ""

    // ---- signals ---------------------------------------------------------
    signal callRequested()
    signal musicRequested()
    signal testRequested()
    signal connectionRequested()
    signal reconnectRequested()
    signal fixRequested()
    signal restoreRequested()
    signal confirmAccepted()
    signal confirmCancelled()

    // ---- external state as readable values -------------------------------
    readonly property var infoObj: info || ({})
    readonly property bool isDark: (Kirigami.Theme.textColor.r * 0.299
                                  + Kirigami.Theme.textColor.g * 0.587
                                  + Kirigami.Theme.textColor.b * 0.114) > 0.5

    // The popup's own foreground colour. Buttons that draw their own icon use
    // this instead of Kirigami.Theme inside the button, where Plasma switches to
    // the system button palette (which can differ from an embedded/popup theme).
    readonly property color fgColor: Kirigami.Theme.textColor

    readonly property color colorA2dp: isDark ? Kirigami.Theme.highlightColor
        : Qt.darker(Kirigami.Theme.highlightColor, 1.4)
    readonly property color colorHfp:  isDark ? "#2cd483" : "#178a4c"
    readonly property color colorOff:  isDark ? "#9aa0a6" : "#59636e"
    readonly property color colorBusy: isDark ? "#e8a33d" : "#a85a00"
    readonly property color colorErr:  isDark ? "#e0553e" : "#c92a2a"

    readonly property color stateColor: {
        if (busy) return colorBusy
        switch (state) {
            case "a2dp":  return colorA2dp
            case "hfp":   return colorHfp
            case "off":   return colorBusy
            case "busy":  return colorBusy
            case "error": return colorErr
            case "none":  return colorOff
            default:      return colorOff
        }
    }

    readonly property string headerIcon: {
        switch (state) {
            case "none":  return "network-bluetooth-inactive-symbolic"
            case "error": return "dialog-warning-symbolic"
            default:      return "audio-headset-symbolic"
        }
    }

    readonly property string batteryIcon: {
        if (!hasBattery) return ""
        var step = Math.max(0, Math.min(100, Math.floor(battery / 10) * 10))
        return "battery-" + (step < 100 ? ("00" + step).slice(-3) : "100") + "-symbolic"
    }

    readonly property string profileChipText: {
        var suffix = codec.length > 0 ? " · " + codec : ""
        switch (state) {
            case "hfp":  return "Call" + suffix
            case "a2dp": return "Music" + suffix
            case "off":  return "Standby"
            default:     return ""
        }
    }

    readonly property bool connected: state === "a2dp" || state === "hfp" || state === "off"
    readonly property bool canAct:    !busy && !testing
    readonly property bool canConnect: canAct && (connected || state === "none")
    readonly property bool canSwitch: connected && canAct
    readonly property bool showProfiles: connected

    readonly property string deviceName: {
        var n = infoObj.device
        return (n && String(n).length > 0) ? String(n) : "XM Headset"
    }
    readonly property string codec: {
        var c = infoObj.codec
        return connected && c && String(c).length > 0 ? String(c) : ""
    }
    readonly property bool hasBattery: {
        var b = infoObj.battery
        return connected && b !== null && b !== undefined && !isNaN(Number(b))
    }
    readonly property int battery: hasBattery ? Number(infoObj.battery) : -1

    readonly property string stateText: {
        switch (state) {
            case "a2dp":  return "Connected · Music profile"
            case "hfp":   return "Connected · Call profile"
            case "off":   return "Connected · standby"
            case "busy":  return "Working…"
            case "error": return "Can't read the audio profile"
            case "none":  return "No headset connected"
            default:      return "Checking…"
        }
    }

    readonly property bool overlayVisible: aboutVisible || confirmVisible
    property bool aboutVisible: false

    readonly property var commandHelp: [
        { cmd: "xm call",            desc: "HFP: microphone + speaker" },
        { cmd: "xm music",           desc: "A2DP: hi-fi output, no mic" },
        { cmd: "xm test",            desc: "5 second microphone check" },
        { cmd: "xm toggle",          desc: "Connect or disconnect the headset" },
        { cmd: "xm reconnect",       desc: "Reset a dead Bluetooth link" },
        { cmd: "xm fix",             desc: "Reconnect, then switch to Call" },
        { cmd: "xm doctor",          desc: "Diagnose the audio stack" },
        { cmd: "xm defaults-reset",  desc: "Hand control back to WirePlumber" }
    ]

    Shortcut {
        sequence: "D"
        enabled: root.canConnect && !root.overlayVisible
        onActivated: root.connectionRequested()
    }

    // ---- keyboard shortcuts ---------------------------------------------
    Shortcut {
        sequence: "C"
        enabled: root.canSwitch && !root.overlayVisible
        onActivated: root.callRequested()
    }
    Shortcut {
        sequence: "M"
        enabled: root.canSwitch && !root.overlayVisible
        onActivated: root.musicRequested()
    }
    Shortcut {
        sequence: "T"
        enabled: root.connected && root.canAct && !root.overlayVisible
        onActivated: root.testRequested()
    }
    Shortcut {
        sequence: "R"
        enabled: root.canAct && !root.overlayVisible
        onActivated: root.reconnectRequested()
    }
    Shortcut {
        sequence: "Escape"
        enabled: root.overlayVisible
        onActivated: {
            if (root.aboutVisible) {
                root.aboutVisible = false
            } else {
                root.confirmCancelled()
            }
        }
    }
    Shortcut {
        sequence: "F"
        enabled: root.connected && root.canAct && !root.overlayVisible
        onActivated: root.fixRequested()
    }

    implicitHeight: mainColumn.implicitHeight + Kirigami.Units.largeSpacing * 2

    // =========================================================================
    //  Main view
    // =========================================================================
    ColumnLayout {
        id: mainColumn
        anchors.fill: parent
        anchors.leftMargin:   Kirigami.Units.largeSpacing
        anchors.rightMargin:  Kirigami.Units.largeSpacing
        anchors.topMargin:    Kirigami.Units.largeSpacing
        anchors.bottomMargin: Kirigami.Units.largeSpacing
        spacing: Kirigami.Units.smallSpacing * 1.5

        // ---- header ------------------------------------------------------
        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing * 1.6

            Rectangle {
                Layout.preferredWidth:  Kirigami.Units.gridUnit * 1.9
                Layout.preferredHeight: Kirigami.Units.gridUnit * 1.9
                radius: Kirigami.Units.smallSpacing * 1.2
                color: Qt.rgba(root.stateColor.r, root.stateColor.g,
                               root.stateColor.b, root.isDark ? 0.20 : 0.13)
                border.width: 1
                border.color: Qt.rgba(root.stateColor.r, root.stateColor.g,
                                      root.stateColor.b, 0.42)
                Behavior on color        { ColorAnimation { duration: 180 } }
                Behavior on border.color { ColorAnimation { duration: 180 } }

                Kirigami.Icon {
                    anchors.centerIn: parent
                    width: 18
                    height: 18
                    source: root.headerIcon
                    color: root.stateColor
                    visible: !root.busy
                    opacity: 1.0
                    Behavior on color   { ColorAnimation  { duration: 180 } }
                    Behavior on opacity { NumberAnimation { duration: 180 } }
                }
                PlasmaComponents3.BusyIndicator {
                    anchors.centerIn: parent
                    width: Kirigami.Units.iconSizes.smallMedium
                    height: width
                    visible: root.busy
                    running: visible
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                PlasmaComponents3.Label {
                    objectName: "deviceNameLabel"
                    Layout.fillWidth: true
                    text: root.deviceName
                    font.bold: true
                    font.pointSize: Kirigami.Theme.defaultFont.pointSize + 1
                    elide: Text.ElideRight
                    Accessible.name: root.deviceName + ". " + root.stateText
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing
                    Chip {
                        visible: root.showText && text.length > 0
                        text: root.profileChipText
                        tint: root.stateColor
                        filled: true
                    }
                    Chip {
                        visible: root.hasBattery
                        text: root.battery + "%"
                        iconName: root.batteryIcon
                    }
                    PlasmaComponents3.Label {
                        visible: !root.connected
                        text: root.busy ? "Working…" : root.stateText
                        font: Kirigami.Theme.smallFont
                        opacity: 0.7
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }
                }
            }

            ActionButton {
                objectName: "connectionButton"
                foregroundColor: root.fgColor
                text: root.busy && root.connectionAction === "connect" ? "Connecting…"
                    : root.busy && root.connectionAction === "disconnect" ? "Disconnecting…"
                    : root.connected ? "Disconnect" : "Connect"
                implicitHeight: Kirigami.Units.gridUnit * 2
                primary: !root.connected
                accentColor: root.colorA2dp
                enabled: root.canConnect
                onClicked: root.connectionRequested()
                PlasmaComponents3.ToolTip {
                    text: root.connected
                        ? "Disconnect the headset and keep it paired (D)"
                        : "Connect your paired headset (D)"
                    visible: parent.hovered
                }
            }

            PlasmaComponents3.ToolButton {
                objectName: "aboutButton"
                Kirigami.Theme.inherit: true
                display: PlasmaComponents3.AbstractButton.IconOnly
                Accessible.name: "About XM Headset"
                icon.name: "help-about-symbolic"
                icon.width: Kirigami.Units.iconSizes.smallMedium
                icon.height: Kirigami.Units.iconSizes.smallMedium
                icon.color: root.fgColor
                onClicked: root.aboutVisible = true
                PlasmaComponents3.ToolTip {
                    text: "About this applet and command reference"
                    visible: parent.hovered
                }
            }
        }

        // ---- transient message -------------------------------------------
        Rectangle {
            Layout.fillWidth: true
            visible: root.showText && root.message.length > 0
            implicitHeight: messageLabel.implicitHeight + Kirigami.Units.smallSpacing * 2
            radius: Kirigami.Units.smallSpacing
            color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g,
                           Kirigami.Theme.textColor.b, root.isDark ? 0.08 : 0.05)
            border.width: 1
            border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g,
                                  Kirigami.Theme.textColor.b, 0.13)

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin:  Kirigami.Units.smallSpacing * 1.5
                anchors.rightMargin: Kirigami.Units.smallSpacing * 1.5
                spacing: Kirigami.Units.smallSpacing

                Kirigami.Icon {
                    Layout.preferredWidth:  Kirigami.Units.iconSizes.small
                    Layout.preferredHeight: Kirigami.Units.iconSizes.small
                    source: "dialog-information-symbolic"
                    opacity: 0.6
                }

                PlasmaComponents3.Label {
                    id: messageLabel
                    Layout.fillWidth: true
                    text: root.message
                    wrapMode: Text.WordWrap
                    font: Kirigami.Theme.smallFont
                    opacity: 0.88
                }
            }
        }

        // ---- recovery (headset absent / unreadable) ----------------------
        Rectangle {
            Layout.fillWidth: true
            visible: root.state === "none" || root.state === "error"
            implicitHeight: recoveryRow.implicitHeight + Kirigami.Units.largeSpacing * 2
            radius: Kirigami.Units.smallSpacing * 1.8
            color: Qt.rgba(root.stateColor.r, root.stateColor.g, root.stateColor.b,
                           root.isDark ? 0.10 : 0.07)
            border.width: 1
            border.color: Qt.rgba(root.stateColor.r, root.stateColor.g, root.stateColor.b, 0.32)

            RowLayout {
                id: recoveryRow
                anchors.fill: parent
                anchors.leftMargin:  Kirigami.Units.largeSpacing
                anchors.rightMargin: Kirigami.Units.largeSpacing
                anchors.topMargin:    Kirigami.Units.smallSpacing
                anchors.bottomMargin: Kirigami.Units.smallSpacing
                spacing: Kirigami.Units.smallSpacing * 1.5

                Kirigami.Icon {
                    Layout.preferredWidth:  Kirigami.Units.iconSizes.medium
                    Layout.preferredHeight: Kirigami.Units.iconSizes.medium
                    source: root.state === "none" ? "network-bluetooth-inactive-symbolic"
                                                  : "dialog-warning-symbolic"
                    color: root.stateColor
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1

                    PlasmaComponents3.Label {
                        Layout.fillWidth: true
                        text: root.state === "none" ? "Headset not connected"
                                                    : "Couldn't read the audio profile"
                        font.bold: true
                        elide: Text.ElideRight
                    }

                    PlasmaComponents3.Label {
                        Layout.fillWidth: true
                        text: root.state === "none"
                            ? "Turn on your paired headset, then choose Connect."
                            : "Reconnect to rebuild the link, or run xm doctor."
                        font: Kirigami.Theme.smallFont
                        opacity: 0.65
                        wrapMode: Text.WordWrap
                    }
                }

                ActionButton {
                    visible: root.state === "error"
                    text: "Reconnect"
                    icon.name: "view-refresh-symbolic"
                    enabled: root.canAct
                    onClicked: root.reconnectRequested()
                }
            }
        }

        // ---- profile cards ----------------------------------------------
        RowLayout {
            objectName: "profileRow"
            Layout.fillWidth: true
            visible: root.showProfiles
            spacing: Kirigami.Units.smallSpacing * 1.6

            ProfileCard {
                objectName: "callButton"
                Layout.preferredWidth: 1
                Layout.fillWidth: true
                cardTitle: "Call"
                cardSubtitle: "Mic + speaker"
                cardIcon: "audio-headset-symbolic"
                accentColor: root.colorHfp
                isActive: root.state === "hfp"
                enabled: root.canSwitch
                tooltipText: "Switch to HFP so the microphone works (C)"
                onClicked: root.callRequested()
            }

            ProfileCard {
                objectName: "musicButton"
                Layout.preferredWidth: 1
                Layout.fillWidth: true
                cardTitle: "Music"
                cardSubtitle: "Hi-fi, no mic"
                cardIcon: "audio-speakers-symbolic"
                accentColor: root.colorA2dp
                isActive: root.state === "a2dp"
                enabled: root.canSwitch
                tooltipText: "Switch to A2DP hi-fi output (M)"
                onClicked: root.musicRequested()
            }
        }

        // ---- microphone test --------------------------------------------
        MicTestPanel {
            objectName: "micPanel"
            enabled: !root.busy
            Layout.fillWidth: true
            visible: root.connected
            testing: root.testing
            countdown: root.countdown
            result: root.testResult
            liveLevels: root.liveLevels
            profileState: root.state
            accentColor: root.stateColor
            onTestRequested: root.testRequested()
        }

        // ---- maintenance -------------------------------------------------
        RowLayout {
            Layout.fillWidth: true
            visible: root.connected
            spacing: Kirigami.Units.smallSpacing * 1.6

            ActionButton {
                Layout.fillWidth: true
                text: "Reconnect"
                icon.name: "view-refresh-symbolic"
                enabled: root.canAct
                onClicked: root.reconnectRequested()
                PlasmaComponents3.ToolTip {
                    text: "Disconnect and reconnect the headset to clear a dead SCO link (R)"
                    visible: parent.hovered
                }
            }

            ActionButton {
                Layout.fillWidth: true
                text: "Fix for meeting"
                icon.name: "tools-symbolic"
                primary: true
                accentColor: root.colorHfp
                enabled: root.canAct
                onClicked: root.fixRequested()
                PlasmaComponents3.ToolTip {
                    text: "Reconnect, then switch to Call (F)"
                    visible: parent.hovered
                }
            }
        }

        Item { Layout.fillHeight: true }

        Kirigami.Separator {
            Layout.fillWidth: true
            opacity: 0.35
        }

        // ---- footer ------------------------------------------------------
        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            PlasmaComponents3.ToolButton {
                id: restoreButton
                Kirigami.Theme.inherit: true
                text: "Restore audio defaults"
                icon.name: "edit-reset-symbolic"
                display: PlasmaComponents3.AbstractButton.TextBesideIcon
                enabled: root.canAct
                onClicked: root.restoreRequested()
                background: Rectangle {
                    radius: Kirigami.Units.smallSpacing
                    color: restoreButton.hovered
                        ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g,
                                  Kirigami.Theme.textColor.b, 0.08)
                        : "transparent"
                }
                contentItem: RowLayout {
                    spacing: Kirigami.Units.smallSpacing

                    Kirigami.Icon {
                        Layout.preferredWidth:  Kirigami.Units.iconSizes.small
                        Layout.preferredHeight: Kirigami.Units.iconSizes.small
                        source: "edit-reset-symbolic"
                        opacity: 0.55
                    }

                    PlasmaComponents3.Label {
                        Layout.fillWidth: true
                        text: "Restore audio defaults"
                        font: Kirigami.Theme.smallFont
                        opacity: 0.62
                    }
                }
                PlasmaComponents3.ToolTip {
                    text: "Remove the WirePlumber drop-in and turn automatic switching back on"
                    visible: parent.hovered
                }
            }

            Item { Layout.fillWidth: true }

            Kirigami.Icon {
                Layout.preferredWidth:  Kirigami.Units.iconSizes.small
                Layout.preferredHeight: Kirigami.Units.iconSizes.small
                visible: root.width >= 400
                source: "utilities-terminal-symbolic"
                opacity: 0.45
            }

            PlasmaComponents3.Label {
                visible: root.width >= 400
                text: "via xm"
                opacity: 0.45
                font: Kirigami.Theme.smallFont
            }

            PlasmaComponents3.ToolButton {
                id: authorButton
                Kirigami.Theme.inherit: true
                text: root.width >= 400 ? "Manoj Goswami" : ""
                icon.name: "user-identity-symbolic"
                display: PlasmaComponents3.AbstractButton.TextBesideIcon
                font: Kirigami.Theme.smallFont
                Accessible.name: "Open Manoj Goswami's GitHub profile"
                onClicked: Qt.openUrlExternally("https://github.com/manojpgoswamigit")
                PlasmaComponents3.ToolTip {
                    text: "Author profile on GitHub"
                    visible: authorButton.hovered
                }
                background: Rectangle {
                    radius: Kirigami.Units.smallSpacing
                    color: authorButton.hovered
                        ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g,
                                  Kirigami.Theme.textColor.b, 0.08)
                        : "transparent"
                }
            }
        }
    }

    // =========================================================================
    //  Overlay: About / confirmation
    // =========================================================================
    Rectangle {
        anchors.fill: parent
        visible: root.overlayVisible
        color: Kirigami.Theme.backgroundColor
        radius: Kirigami.Units.smallSpacing * 1.5
        border.width: 1
        border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g,
                              Kirigami.Theme.textColor.b, 0.18)
        clip: true
        z: 99

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.largeSpacing
            spacing: Kirigami.Units.smallSpacing * 1.5

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing * 1.5

                Rectangle {
                    Layout.preferredWidth:  Kirigami.Units.gridUnit * 2.2
                    Layout.preferredHeight: Kirigami.Units.gridUnit * 2.2
                    radius: width / 2
                    color: Qt.rgba((root.aboutVisible ? root.colorA2dp : root.colorBusy).r,
                                   (root.aboutVisible ? root.colorA2dp : root.colorBusy).g,
                                   (root.aboutVisible ? root.colorA2dp : root.colorBusy).b,
                                   root.isDark ? 0.18 : 0.12)

                    Kirigami.Icon {
                        anchors.centerIn: parent
                        width:  Kirigami.Units.iconSizes.smallMedium
                        height: Kirigami.Units.iconSizes.smallMedium
                        source: root.aboutVisible ? "audio-headset-symbolic"
                                                  : "dialog-warning-symbolic"
                        color: root.aboutVisible ? root.colorA2dp : root.colorBusy
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    PlasmaComponents3.Label {
                        Layout.fillWidth: true
                        text: root.aboutVisible ? "About XM Headset" : root.confirmTitle
                        font.bold: true
                        font.pointSize: Kirigami.Theme.defaultFont.pointSize + 1
                        elide: Text.ElideRight
                    }

                    PlasmaComponents3.Label {
                        Layout.fillWidth: true
                        text: root.aboutVisible ? "Plasma widget for PipeWire" : "Please confirm"
                        font: Kirigami.Theme.smallFont
                        opacity: 0.58
                        elide: Text.ElideRight
                    }
                }

                PlasmaComponents3.ToolButton {
                    Kirigami.Theme.inherit: true
                    display: PlasmaComponents3.AbstractButton.IconOnly
                    Accessible.name: "Close"
                    icon.name: "window-close-symbolic"
                    icon.width: Kirigami.Units.iconSizes.smallMedium
                    icon.height: Kirigami.Units.iconSizes.smallMedium
                    icon.color: root.fgColor
                    onClicked: {
                        if (root.aboutVisible) {
                            root.aboutVisible = false
                        } else {
                            root.confirmCancelled()
                        }
                    }
                }
            }

            Kirigami.Separator {
                Layout.fillWidth: true
                opacity: 0.3
            }

            PlasmaComponents3.ScrollView {
                id: overlayScroll
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                PlasmaComponents3.ScrollBar.horizontal.policy: PlasmaComponents3.ScrollBar.AlwaysOff

                ColumnLayout {
                    width: overlayScroll.availableWidth
                    spacing: Kirigami.Units.smallSpacing * 1.3

                    // ---- About ------------------------------------------
                    ColumnLayout {
                        Layout.fillWidth: true
                        visible: root.aboutVisible
                        spacing: Kirigami.Units.smallSpacing * 1.2

                        PlasmaComponents3.Label {
                            Layout.fillWidth: true
                            text: "One click switches your Bluetooth headset between a "
                                + "mic-ready call profile and hi-fi music. Every button runs "
                                + "the xm command - this applet never touches the audio stack itself."
                            wrapMode: Text.WordWrap
                            opacity: 0.85
                        }

                        PlasmaComponents3.Label {
                            Layout.fillWidth: true
                            text: "Commands"
                            font.bold: true
                            opacity: 0.6
                            Layout.topMargin: Kirigami.Units.smallSpacing
                        }

                        TextMetrics {
                            id: commandMetrics
                            font.family: "monospace"
                            font.pointSize: Kirigami.Theme.smallFont.pointSize
                            font.bold: true
                            text: "xm defaults-reset"
                        }

                        Repeater {
                            model: root.commandHelp

                            RowLayout {
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: Kirigami.Units.smallSpacing * 1.2

                                PlasmaComponents3.Label {
                                    Layout.preferredWidth: commandMetrics.advanceWidth
                                                           + Kirigami.Units.smallSpacing
                                    text: modelData.cmd
                                    font.family: "monospace"
                                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                                    font.bold: true
                                    elide: Text.ElideRight
                                }

                                PlasmaComponents3.Label {
                                    Layout.fillWidth: true
                                    text: modelData.desc
                                    font: Kirigami.Theme.smallFont
                                    opacity: 0.7
                                    elide: Text.ElideRight
                                }
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.topMargin: Kirigami.Units.smallSpacing
                            implicitHeight: rollbackBox.implicitHeight
                                          + Kirigami.Units.smallSpacing * 2
                            radius: Kirigami.Units.smallSpacing
                            color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g,
                                           Kirigami.Theme.textColor.b, root.isDark ? 0.07 : 0.04)
                            border.width: 1
                            border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g,
                                                  Kirigami.Theme.textColor.b, 0.12)

                            ColumnLayout {
                                id: rollbackBox
                                anchors.fill: parent
                                anchors.margins: Kirigami.Units.smallSpacing * 1.2
                                spacing: 2

                                PlasmaComponents3.Label {
                                    text: "Remove everything, restore defaults (from the repo root):"
                                    font: Kirigami.Theme.smallFont
                                    opacity: 0.6
                                    wrapMode: Text.WordWrap
                                }

                                PlasmaComponents3.Label {
                                    text: "./rollback.sh"
                                    font.family: "monospace"
                                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                                    font.bold: true
                                }
                            }
                        }

                        PlasmaComponents3.Label {
                            Layout.fillWidth: true
                            text: "Shortcuts: C Call · M Music · T Test · D Connect/disconnect · R Reconnect · F Fix"
                            font: Kirigami.Theme.smallFont
                            opacity: 0.5
                            wrapMode: Text.WordWrap
                        }

                        Kirigami.Separator {
                            Layout.fillWidth: true
                            Layout.topMargin: Kirigami.Units.smallSpacing
                            opacity: 0.3
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.smallSpacing

                            PlasmaComponents3.ToolButton {
                                id: aboutAuthorButton
                                Kirigami.Theme.inherit: true
                                text: "Created by Manoj Goswami"
                                icon.name: "user-identity-symbolic"
                                display: PlasmaComponents3.AbstractButton.TextBesideIcon
                                font: Kirigami.Theme.smallFont
                                Accessible.name: "Open Manoj Goswami's GitHub profile"
                                onClicked: Qt.openUrlExternally("https://github.com/manojpgoswamigit")
                                PlasmaComponents3.ToolTip {
                                    text: "Author profile on GitHub"
                                    visible: aboutAuthorButton.hovered
                                }
                            }

                            Item { Layout.fillWidth: true }

                            PlasmaComponents3.ToolButton {
                                id: aboutRepoButton
                                Kirigami.Theme.inherit: true
                                text: "GitHub repo"
                                font: Kirigami.Theme.smallFont
                                Accessible.name: "Open the xm GitHub repository"
                                contentItem: RowLayout {
                                    spacing: Kirigami.Units.smallSpacing

                                    GitHubIcon {
                                        Layout.preferredWidth: Kirigami.Units.iconSizes.small
                                        Layout.preferredHeight: Kirigami.Units.iconSizes.small
                                        color: Kirigami.Theme.textColor
                                        opacity: 0.9
                                    }

                                    PlasmaComponents3.Label {
                                        text: "GitHub repo"
                                        font: Kirigami.Theme.smallFont
                                    }
                                }
                                onClicked: Qt.openUrlExternally("https://github.com/manojpgoswamigit/xm-mic-audio-fix")
                                PlasmaComponents3.ToolTip {
                                    text: "Source code and documentation"
                                    visible: aboutRepoButton.hovered
                                }
                            }
                        }
                    }

                    // ---- confirmation ----------------------------------
                    ColumnLayout {
                        Layout.fillWidth: true
                        visible: root.confirmVisible
                        spacing: Kirigami.Units.smallSpacing * 1.5

                        PlasmaComponents3.Label {
                            Layout.fillWidth: true
                            text: root.confirmBody
                            wrapMode: Text.WordWrap
                            opacity: 0.88
                        }
                    }
                }
            }

            Kirigami.Separator {
                Layout.fillWidth: true
                opacity: 0.3
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing * 1.5

                Item { Layout.fillWidth: true }

                ActionButton {
                    visible: !root.aboutVisible
                    text: "Cancel"
                    onClicked: root.confirmCancelled()
                }

                ActionButton {
                    text: root.aboutVisible ? "Done" : "Do it"
                    primary: true
                    accentColor: root.colorA2dp
                    onClicked: {
                        if (root.aboutVisible) {
                            root.aboutVisible = false
                        } else {
                            root.confirmAccepted()
                        }
                    }
                }
            }
        }
    }
}
