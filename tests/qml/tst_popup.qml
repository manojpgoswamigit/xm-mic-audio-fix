import QtQuick
import QtTest
import "../../plasmoid/contents/ui"

TestCase {
    id: testCase
    name: "HeadsetPopup"
    visible: true
    width: 360
    height: 468
    when: windowShown

    HeadsetPopup {
        id: popup
        anchors.fill: parent
        info: ({device: "Sony WH-1000XM5 Wireless Headphones", codec: "LDAC", battery: 70})
    }
    SignalSpy { id: connectionSpy; target: popup; signalName: "connectionRequested" }

    function init() {
        popup.state = "a2dp"
        popup.busy = false
        popup.testing = false
        popup.testResult = null
        popup.message = ""
        popup.connectionAction = ""
        connectionSpy.clear()
        wait(50)
    }

    function test_connection_action() {
        var button = findChild(popup, "connectionButton")
        compare(button.text, "Disconnect")
        mouseClick(button)
        compare(connectionSpy.count, 1)
        popup.state = "none"
        compare(button.text, "Connect")
        wait(50)
        mouseClick(button)
        compare(connectionSpy.count, 2)
    }

    function test_busy_keeps_layout_and_describes_action() {
        var button = findChild(popup, "connectionButton")
        var card = findChild(popup, "callButton")
        var previousY = card.mapToItem(popup, 0, 0).y
        popup.busy = true
        popup.connectionAction = "disconnect"
        compare(button.text, "Disconnecting…")
        verify(!button.enabled)
        verify(card.visible)
        compare(card.mapToItem(popup, 0, 0).y, previousY)
        popup.busy = false
    }

    function test_idle_mic_is_compact() {
        var mic = findChild(popup, "micPanel")
        verify(mic !== null)
        verify(mic.height < 110, "Idle microphone panel should leave room for primary actions")
        popup.testing = true
        wait(200)
        verify(mic.height > 130)
    }
    function test_header_fits_long_device_name_data() {
        return [
            {tag: "idle", busy: false, action: ""},
            {tag: "connecting", busy: true, action: "connect"},
            {tag: "disconnecting", busy: true, action: "disconnect"}
        ]
    }

    function test_header_fits_long_device_name(data) {
        popup.busy = data.busy
        popup.connectionAction = data.action
        wait(100)
        var name = findChild(popup, "deviceNameLabel")
        var button = findChild(popup, "connectionButton")
        var nameEnd = name.mapToItem(popup, name.width, 0).x
        var buttonStart = button.mapToItem(popup, 0, 0).x
        verify(name.width > 80)
        verify(nameEnd <= buttonStart, "Device name must not overlap connection control")
        verify(button.mapToItem(popup, button.width, 0).x <= popup.width)
        var about = findChild(popup, "aboutButton")
        verify(about.mapToItem(popup, about.width, 0).x <= popup.width, "Busy header exceeds popup width")
        var music = findChild(popup, "musicButton")
        verify(music.mapToItem(popup, music.width, 0).x <= popup.width, "Profile row exceeds popup width")
    }

    function test_keyboard_focus_and_busy_safety() {
        var button = findChild(popup, "connectionButton")
        button.forceActiveFocus()
        verify(button.activeFocus)
        keyClick(Qt.Key_Space)
        compare(connectionSpy.count, 1)
        popup.busy = true
        mouseClick(button)
        keyClick(Qt.Key_D)
        compare(connectionSpy.count, 1)
    }

    function test_content_fits_data() {
        return [
            { tag: "music", state: "a2dp", testing: false },
            { tag: "call", state: "hfp", testing: false },
            { tag: "live-test", state: "hfp", testing: true },
            { tag: "disconnected", state: "none", testing: false },
            { tag: "error", state: "error", testing: false }
        ]
    }

    function test_content_fits(data) {
        popup.state = data.state
        popup.testing = data.testing
        wait(100)
        verify(popup.implicitHeight <= popup.height,
            "Content height " + popup.implicitHeight + " exceeds popup " + popup.height)
    }

}
