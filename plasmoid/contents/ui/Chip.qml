// Small pill used for the profile, battery and mic verdict chips.
import QtQuick
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

Item {
    id: chip

    property string text: ""
    property string iconName: ""
    property color tint: Kirigami.Theme.textColor
    property bool filled: false

    implicitWidth: row.implicitWidth + Kirigami.Units.smallSpacing * 2
    implicitHeight: Kirigami.Units.gridUnit * 1.3

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: Qt.rgba(chip.tint.r, chip.tint.g, chip.tint.b,
                       chip.filled ? 0.16 : 0.07)
        border.width: 1
        border.color: Qt.rgba(chip.tint.r, chip.tint.g, chip.tint.b,
                              chip.filled ? 0.42 : 0.16)
    }

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: Kirigami.Units.smallSpacing * 0.6

        Kirigami.Icon {
            visible: chip.iconName.length > 0
            source: chip.iconName
            Layout.preferredWidth: Kirigami.Units.iconSizes.small
            Layout.preferredHeight: Kirigami.Units.iconSizes.small
            color: chip.tint
            opacity: 0.85
        }

        PlasmaComponents3.Label {
            text: chip.text
            font: Kirigami.Theme.smallFont
            color: chip.tint
            opacity: 0.9
        }
    }
}
