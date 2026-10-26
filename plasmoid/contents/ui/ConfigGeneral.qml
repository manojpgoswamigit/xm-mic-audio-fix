// =============================================================================
//  General configuration for the XM Headset applet.
//
//  Plasma's configuration dialog copies each key from contents/config/main.xml
//  into a `cfg_<key>` property on this page, then saves those properties back
//  when the user presses Apply. Keep the cfg_ aliases in lockstep with
//  main.xml; tests/test-widget-config.sh checks that contract.
// =============================================================================

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts

import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami

KCM.SimpleKCM {
    id: page

    property alias cfg_xmPath:        xmPathField.text
    property alias cfg_pollInterval:  pollSpin.value
    property alias cfg_showText:      showTextCheck.checked
    property alias cfg_confirmReset:  confirmCheck.checked
    property alias cfg_notifications: notifyCheck.checked

    Kirigami.FormLayout {

        // ---- command -------------------------------------------------------
        QQC2.TextField {
            id: xmPathField
            Kirigami.FormData.label: i18nc("@label:command", "Command:")
            Layout.fillWidth: true
            placeholderText: "~/.local/bin/xm"
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
            Kirigami.FormData.label: i18nc("@label:spinbox", "Refresh interval (seconds):")
            from: 1
            to: 30
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
        }

        QQC2.Switch {
            id: confirmCheck
            Kirigami.FormData.label: i18nc("@option:check", "Ask before restoring defaults:")
        }

        QQC2.Switch {
            id: notifyCheck
            Kirigami.FormData.label: i18nc("@option:check", "Notify when an action finishes:")
        }

        Item {
            Layout.fillHeight: true
        }
    }
}
