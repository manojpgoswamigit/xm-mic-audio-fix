// =============================================================================
//  Configuration UI for the XM Headset applet.
//
//  Deliberately small: the applet is safe at its defaults, so this only
//  exposes the knobs a power user might actually want. Values are written
//  straight into `configModel`, which Plasma saves for us.
// =============================================================================

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts

import org.kde.plasma.configuration
import org.kde.kirigami as Kirigami

ConfigPage {
    id: page

    property alias cfgPollInterval: pollSpin.value
    property alias cfgShowText:    showTextCheck.checked
    property alias cfgConfirm:     confirmCheck.checked
    property alias cfgNotify:      notifyCheck.checked
    property alias cfgXmPath:      xmPathField.text

    Kirigami.FormLayout {
        anchors.fill: parent
        anchors.margins: Kirigami.Units.gridUnit * 0.5

        // ---- command -------------------------------------------------------
        QQC2.TextField {
            id: xmPathField
            Kirigami.FormData.label: i18n("Command:")
            Layout.fillWidth: true
            text: configModel.xmPath
            placeholderText: "~/.local/bin/xm"
            onTextChanged: configModel.xmPath = text
        }

        QQC2.Label {
            Layout.fillWidth: true
            text: i18n("Leave empty to use ~/.local/bin/xm.")
            opacity: 0.7
            font: Kirigami.Theme.smallFont
        }

        // ---- polling -------------------------------------------------------
        QQC2.SpinBox {
            id: pollSpin
            Kirigami.FormData.label: i18n("Refresh interval (seconds):")
            from: 1
            to: 30
            value: configModel.pollInterval
            onValueModified: configModel.pollInterval = value
        }

        QQC2.Label {
            Layout.fillWidth: true
            text: i18n("xm answers in about 15 ms, so 2 seconds is already plenty.")
            opacity: 0.7
            font: Kirigami.Theme.smallFont
        }

        // ---- switches ------------------------------------------------------
        QQC2.Switch {
            id: showTextCheck
            Kirigami.FormData.label: i18nc("@option:check", "Show profile and result text:")
            checked: configModel.showText
            onToggled: configModel.showText = checked
        }

        QQC2.Switch {
            id: confirmCheck
            Kirigami.FormData.label: i18nc("@option:check", "Ask before restoring defaults:")
            checked: configModel.confirmReset
            onToggled: configModel.confirmReset = checked
        }

        QQC2.Switch {
            id: notifyCheck
            Kirigami.FormData.label: i18nc("@option:check", "Notify when an action finishes:")
            checked: configModel.notifications
            onToggled: configModel.notifications = checked
        }

        Item {
            Layout.fillHeight: true
        }
    }
}
