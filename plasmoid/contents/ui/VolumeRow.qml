// =============================================================================
//  VolumeRow - one headset volume control (speaker or microphone)
// =============================================================================
//    [icon chip]  Name ..................... 54%
//                 ===========O---------------
//
//  * The icon chip is the mute toggle: tinted when live, grey + muted icon
//    when muted. The slider keeps its level, so unmuting restores it.
//  * A Plasma Slider underneath, so keyboard (arrows, PgUp/PgDn, Home/End),
//    mouse wheel, focus and accessibility come from Plasma itself.
//  * Pure view: `value` / `muted` come in, `valueRequested` / `muteRequested`
//    go out. While the user is dragging, incoming values never yank the
//    handle; it re-syncs on release.
// =============================================================================

import QtQuick
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

Item {
    id: row

    property string name:          "Speaker"
    property string iconName:      "audio-volume-high-symbolic"
    property string mutedIconName: "audio-volume-muted-symbolic"
    property color  accentColor:   Kirigami.Theme.highlightColor
    property int    value:         -1        // 0-100, -1 = unknown
    property bool   muted:         false
    property bool   available:     true      // the device exists right now
    property string caption:       ""        // shown instead of the level when unavailable

    signal valueRequested(int value)
    signal muteRequested(bool muted)

    readonly property bool known:  value >= 0
    readonly property bool usable: enabled && available && known

    readonly property bool isDark: (Kirigami.Theme.textColor.r * 0.299
                                  + Kirigami.Theme.textColor.g * 0.587
                                  + Kirigami.Theme.textColor.b * 0.114) > 0.5
    readonly property color textColor: Kirigami.Theme.textColor
    readonly property color greyColor: Qt.rgba(textColor.r, textColor.g, textColor.b,
                                               isDark ? 0.38 : 0.34)
    readonly property color tint: muted || !usable ? greyColor : accentColor

    readonly property int shownValue: Math.round(slider.value)
    readonly property string valueText: {
        if (!available && caption.length > 0) return caption
        if (!known) return "—"
        if (muted) return "Muted"
        return shownValue + "%"
    }

    implicitHeight: Math.max(muteButton.implicitHeight, textCol.implicitHeight)
    implicitWidth: Kirigami.Units.gridUnit * 14
    opacity: usable ? 1.0 : 0.62
    Behavior on opacity { NumberAnimation { duration: 160 } }

    Accessible.role: Accessible.Grouping
    Accessible.name: name + " volume"

    // External value -> handle, except while the user owns the handle.
    // Reads `value` directly: in onValueChanged the `known` binding may not
    // have re-evaluated yet.
    function syncFromValue() {
        if (!slider.pressed) {
            slider.value = row.value >= 0 ? Math.min(100, row.value) : 0
        }
    }
    onValueChanged: syncFromValue()
    Component.onCompleted: syncFromValue()

    // Self-correct: shortly after the user's last change, show the real level
    // again even if it never changed (for example the command failed).
    Timer {
        id: resyncTimer
        interval: 2000
        onTriggered: row.syncFromValue()
    }

    RowLayout {
        anchors.fill: parent
        spacing: Kirigami.Units.smallSpacing * 1.6

        // ---- mute toggle ---------------------------------------------------
        PlasmaComponents3.AbstractButton {
            id: muteButton
            objectName: row.objectName + "Mute"
            Layout.alignment: Qt.AlignVCenter
            implicitWidth:  Kirigami.Units.gridUnit * 1.6
            implicitHeight: Kirigami.Units.gridUnit * 1.6
            enabled: row.usable
            hoverEnabled: true
            activeFocusOnTab: true
            Accessible.name: (row.muted ? "Unmute " : "Mute ") + row.name.toLowerCase()
            onClicked: row.muteRequested(!row.muted)

            PlasmaComponents3.ToolTip {
                text: (row.muted ? "Unmute the headset " : "Mute the headset ")
                      + row.name.toLowerCase()
                visible: muteButton.hovered && muteButton.enabled
            }

            background: Rectangle {
                radius: width / 2
                color: Qt.rgba(row.tint.r, row.tint.g, row.tint.b,
                               muteButton.down ? 0.30
                               : muteButton.hovered ? 0.24
                               : (row.isDark ? 0.17 : 0.12))
                border.width: muteButton.visualFocus ? 2 : 1
                border.color: Qt.rgba(row.tint.r, row.tint.g, row.tint.b,
                                      muteButton.visualFocus ? 0.85 : 0.36)
                Behavior on color        { ColorAnimation { duration: 140 } }
                Behavior on border.color { ColorAnimation { duration: 140 } }
            }

            contentItem: Item {
                Kirigami.Icon {
                    anchors.centerIn: parent
                    width:  Kirigami.Units.iconSizes.small
                    height: Kirigami.Units.iconSizes.small
                    source: row.muted ? row.mutedIconName : row.iconName
                    color: row.muted || !row.usable ? row.textColor : row.accentColor
                    opacity: row.muted || !row.usable ? 0.7 : 1.0
                    Behavior on color { ColorAnimation { duration: 140 } }
                }
            }
        }

        // ---- name, level and track -----------------------------------------
        ColumnLayout {
            id: textCol
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 0

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                PlasmaComponents3.Label {
                    Layout.fillWidth: true
                    text: row.name
                    font: Kirigami.Theme.smallFont
                    opacity: 0.78
                    elide: Text.ElideRight
                }

                PlasmaComponents3.Label {
                    objectName: row.objectName + "Value"
                    text: row.valueText
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    font.bold: row.usable && !row.muted
                    color: row.usable && !row.muted ? row.accentColor : row.textColor
                    opacity: row.usable && !row.muted ? 1.0 : 0.6
                }
            }

            PlasmaComponents3.Slider {
                id: slider
                objectName: row.objectName + "Slider"
                Layout.fillWidth: true
                from: 0
                to: 100
                stepSize: 5
                wheelEnabled: true
                live: true
                enabled: row.usable
                hoverEnabled: true
                activeFocusOnTab: true
                implicitHeight: Kirigami.Units.gridUnit * 0.95
                padding: 0
                leftPadding: 8      // half the handle, so it never clips
                rightPadding: 8

                Accessible.name: row.name + " volume"

                // Keyboard and wheel do not set `pressed`, so every change the
                // user makes arrives through `moved`.
                onMoved: {
                    resyncTimer.restart()
                    row.valueRequested(Math.round(value))
                }
                onPressedChanged: if (!pressed) row.syncFromValue()

                background: Item {
                    x: slider.leftPadding
                    y: slider.topPadding + slider.availableHeight / 2 - height / 2
                    width: slider.availableWidth
                    height: 6

                    Rectangle {
                        anchors.fill: parent
                        radius: height / 2
                        color: Qt.rgba(row.textColor.r, row.textColor.g, row.textColor.b,
                                       row.isDark ? 0.14 : 0.11)
                    }

                    Rectangle {
                        width: Math.max(height, slider.visualPosition * parent.width)
                        height: parent.height
                        radius: height / 2
                        visible: row.known
                        color: row.tint
                        Behavior on color { ColorAnimation { duration: 140 } }
                    }
                }

                handle: Item {
                    x: slider.leftPadding + slider.visualPosition * slider.availableWidth - width / 2
                    y: slider.topPadding + slider.availableHeight / 2 - height / 2
                    width: 16
                    height: 16
                    visible: row.known


                    // Focus halo
                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.width + 8
                        height: width
                        radius: width / 2
                        color: Qt.rgba(row.tint.r, row.tint.g, row.tint.b, 0.22)
                        visible: slider.visualFocus
                    }

                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.width
                        height: width
                        radius: width / 2
                        scale: slider.pressed ? 1.15 : slider.hovered ? 1.08 : 1.0
                        color: row.tint
                        border.width: 2
                        border.color: Kirigami.Theme.backgroundColor
                        Behavior on scale { NumberAnimation { duration: 120 } }
                        Behavior on color { ColorAnimation  { duration: 140 } }
                    }
                }
            }
        }
    }
}
