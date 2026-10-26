// =============================================================================
//  ProfileCard - one large Call / Music target
// =============================================================================
//  A Plasma Button with a custom, tactile card body:
//    * tinted icon chip
//    * title + one-line explanation
//    * active card: 2px accent border, tinted fill, check badge
//    * subtle press / hover motion, 120-160 ms, no bounce
//  The root is a Button so focus, Tab order, Enter/Space and accessibility
//  come from Plasma itself instead of a hand-rolled MouseArea.
// =============================================================================

import QtQuick
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

PlasmaComponents3.Button {
    id: card

    property string cardTitle:       ""
    property string cardSubtitle:    ""
    property string cardIcon:        "audio-headset-symbolic"
    property string tooltipText:     ""
    property color  accentColor:     Kirigami.Theme.highlightColor
    property bool   isActive:        false

    readonly property bool isDark: (Kirigami.Theme.textColor.r * 0.299
                                  + Kirigami.Theme.textColor.g * 0.587
                                  + Kirigami.Theme.textColor.b * 0.114) > 0.5

    // Follow the popup's palette instead of the system button palette.
    Kirigami.Theme.inherit: true

    implicitHeight: Kirigami.Units.gridUnit * 3.2
    padding: 0
    hoverEnabled: true
    activeFocusOnTab: true
    opacity: enabled ? 1.0 : (isActive ? 0.9 : 0.68)

    Accessible.name: cardTitle + ". " + cardSubtitle
                     + (isActive ? ". Active profile." : "")

    PlasmaComponents3.ToolTip {
        text: card.tooltipText
        visible: card.hovered && card.tooltipText.length > 0
    }

    background: Rectangle {
        radius: Kirigami.Units.smallSpacing * 1.8
        color: {
            if (card.isActive) {
                return Qt.rgba(card.accentColor.r, card.accentColor.g,
                               card.accentColor.b, card.down ? 0.26 : 0.14)
            }
            if (card.down) {
                return Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g,
                               Kirigami.Theme.textColor.b, 0.11)
            }
            if (card.hovered) {
                return Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g,
                               Kirigami.Theme.textColor.b, card.isDark ? 0.09 : 0.06)
            }
            return Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g,
                           Kirigami.Theme.textColor.b, card.isDark ? 0.05 : 0.035)
        }
        border.width: card.isActive ? 2 : 1
        border.color: card.isActive
            ? card.accentColor
            : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g,
                      Kirigami.Theme.textColor.b, card.hovered ? 0.26 : 0.12)

        Behavior on color              { ColorAnimation { duration: 140 } }
        Behavior on border.color       { ColorAnimation { duration: 140 } }
    }

    contentItem: RowLayout {
        anchors.fill: parent
        anchors.leftMargin:   Kirigami.Units.smallSpacing * 1.5
        anchors.rightMargin:  Kirigami.Units.smallSpacing * 1.5
        spacing: Kirigami.Units.smallSpacing

        Kirigami.Icon {
            source: card.cardIcon
            Layout.preferredWidth:  Kirigami.Units.iconSizes.smallMedium
            Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
            color: card.isActive ? card.accentColor : Kirigami.Theme.textColor
            opacity: card.isActive ? 1.0 : 0.75
            Behavior on color { ColorAnimation { duration: 140 } }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                text: card.cardTitle
                font.bold: true
                font.pointSize: Kirigami.Theme.defaultFont.pointSize + 1
                color: card.isActive ? card.accentColor : Kirigami.Theme.textColor
                elide: Text.ElideRight
                Behavior on color { ColorAnimation { duration: 140 } }
            }

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                text: card.cardSubtitle
                font: Kirigami.Theme.smallFont
                opacity: card.isActive ? 0.9 : 0.62
                elide: Text.ElideRight
            }
        }

        Rectangle {
            visible: card.isActive
            Layout.preferredWidth:  Kirigami.Units.gridUnit * 1.25
            Layout.preferredHeight: Kirigami.Units.gridUnit * 1.25
            radius: width / 2
            color: card.accentColor

            Kirigami.Icon {
                anchors.centerIn: parent
                width:  Kirigami.Units.iconSizes.small
                height: Kirigami.Units.iconSizes.small
                source: "checkmark-symbolic"
                color: (card.accentColor.r * 0.299
                      + card.accentColor.g * 0.587
                      + card.accentColor.b * 0.114) > 0.62 ? "#101314" : "#ffffff"
            }
        }
    }

    scale: down ? 0.975 : 1.0
    Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
}
