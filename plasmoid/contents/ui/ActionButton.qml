// =============================================================================
//  ActionButton - compact, theme-aware button used throughout the popup
// =============================================================================
//  Plasma's default button chrome is fine on a real panel but very heavy in a
//  small popup (and it depends on the host palette, which makes offscreen
//  screenshots unusable). This keeps the button behaviour - focus, hover,
//  press, accessibility - and draws a lighter surface from Kirigami.Theme
//  colours only.
// =============================================================================

import QtQuick
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

PlasmaComponents3.Button {
    id: button

    property color foregroundColor: Kirigami.Theme.textColor
    property bool  primary: false
    property color accentColor: Kirigami.Theme.highlightColor

    // Follow the popup's palette instead of the system button palette.
    Kirigami.Theme.inherit: true

    implicitHeight: Kirigami.Units.gridUnit * 2.45
    leftPadding:  Kirigami.Units.largeSpacing
    rightPadding: Kirigami.Units.largeSpacing
    topPadding:   0
    bottomPadding: 0
    hoverEnabled: true
    activeFocusOnTab: true

    readonly property bool isDark: (Kirigami.Theme.textColor.r * 0.299
                                  + Kirigami.Theme.textColor.g * 0.587
                                  + Kirigami.Theme.textColor.b * 0.114) > 0.5

    background: Rectangle {
        radius: Kirigami.Units.smallSpacing * 1.4
        color: {
            if (button.primary) {
                return Qt.rgba(button.accentColor.r, button.accentColor.g,
                               button.accentColor.b,
                               button.down ? 0.30 : (button.hovered ? 0.23 : 0.14))
            }
            return Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g,
                           Kirigami.Theme.textColor.b,
                           button.down ? 0.14 : (button.hovered ? 0.10 : 0.055))
        }
        border.width: 1
        border.color: button.primary
            ? Qt.rgba(button.accentColor.r, button.accentColor.g,
                      button.accentColor.b, button.activeFocus ? 1.0 : (button.hovered ? 0.62 : 0.42))
            : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g,
                      Kirigami.Theme.textColor.b, button.activeFocus ? 0.8 : (button.hovered ? 0.26 : 0.14))

        Behavior on color        { ColorAnimation { duration: 130 } }
        Behavior on border.color { ColorAnimation { duration: 130 } }
    }

    contentItem: RowLayout {
        spacing: Kirigami.Units.smallSpacing * 1.2

        Kirigami.Icon {
            visible: button.icon.name.length > 0
            Layout.preferredWidth:  Kirigami.Units.iconSizes.small
            Layout.preferredHeight: Kirigami.Units.iconSizes.small
            source: button.icon.name
            color: button.primary ? button.accentColor : button.foregroundColor
            opacity: 0.95
        }

        PlasmaComponents3.Label {
            Layout.fillWidth: true
            text: button.text
            font: Kirigami.Theme.defaultFont
            color: button.primary ? button.accentColor : button.foregroundColor
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            opacity: 1.0
        }
    }

    opacity: enabled ? 1.0 : 0.7
}
