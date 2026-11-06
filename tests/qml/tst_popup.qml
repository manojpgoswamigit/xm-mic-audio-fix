import QtQuick
import QtTest
import "../../plasmoid/contents/ui"

TestCase {
    id: testCase
    name: "HeadsetPopup"
    visible: true
    width: 360
    // Height budget for the tallest state (live mic test in Call). Raised
    // from 468 when the volume section was added.
    height: 500
    when: windowShown

    HeadsetPopup {
        id: popup
        anchors.fill: parent
        info: testCase.baseInfo()
    }
    SignalSpy { id: connectionSpy; target: popup; signalName: "connectionRequested" }
    // Per-control recorders on top of the two shared signals.
    QtObject { id: speakerVolumeSpy; property int count: 0; property var signalArguments: [] }
    QtObject { id: speakerMuteSpy;   property int count: 0; property var signalArguments: [] }
    QtObject { id: micVolumeSpy;     property int count: 0; property var signalArguments: [] }
    QtObject { id: micMuteSpy;       property int count: 0; property var signalArguments: [] }
    function record(spy, arg) {
        var a = spy.signalArguments.slice(); a.push([arg]); spy.signalArguments = a; spy.count = a.length
    }
    function clearSpy(spy) { spy.signalArguments = []; spy.count = 0 }
    Connections {
        target: popup
        function onVolumeRequested(which, value) { testCase.record(which === "mic" ? micVolumeSpy : speakerVolumeSpy, value) }
        function onMuteRequested(which, muted)   { testCase.record(which === "mic" ? micMuteSpy : speakerMuteSpy, muted) }
    }

    function baseInfo() {
        return {device: "Sony WH-1000XM5 Wireless Headphones", codec: "LDAC", battery: 70,
                speaker_volume: 54, speaker_muted: false, mic_volume: 70, mic_muted: false}
    }
    function withInfo(fields) {
        var o = baseInfo()
        for (var k in fields) o[k] = fields[k]
        popup.info = o
    }

    function init() {
        popup.state = "a2dp"
        popup.busy = false
        popup.testing = false
        popup.testResult = null
        popup.message = ""
        popup.connectionAction = ""
        // Blank first, so every row sees a value change and re-syncs.
        popup.info = ({})
        popup.info = baseInfo()
        connectionSpy.clear()
        clearSpy(speakerVolumeSpy)
        clearSpy(speakerMuteSpy)
        clearSpy(micVolumeSpy)
        clearSpy(micMuteSpy)
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

    // ---- volume ---------------------------------------------------------
    function test_volume_visibility_data() {
        return [
            { tag: "music",        state: "a2dp",    panel: true,  speaker: true,  mic: false, micText: "Call profile only" },
            { tag: "call",         state: "hfp",     panel: true,  speaker: true,  mic: true,  micText: "70%" },
            { tag: "standby",      state: "off",     panel: false },
            { tag: "disconnected", state: "none",    panel: false },
            { tag: "error",        state: "error",   panel: false },
            { tag: "loading",      state: "loading", panel: false }
        ]
    }

    function test_volume_visibility(data) {
        popup.state = data.state
        wait(50)
        var panel = findChild(popup, "volumePanel")
        compare(panel.visible, data.panel)
        if (!data.panel) {
            return
        }
        var speaker = findChild(popup, "speakerVolume")
        var mic = findChild(popup, "micVolume")
        verify(speaker.visible && mic.visible, "Both rows stay visible so the height never jumps")
        compare(speaker.usable, data.speaker)
        compare(findChild(popup, "speakerVolumeSlider").enabled, data.speaker)
        compare(mic.usable, data.mic)
        compare(findChild(popup, "micVolumeSlider").enabled, data.mic)
        compare(findChild(popup, "micVolumeMute").enabled, data.mic)
        compare(findChild(popup, "micVolumeValue").text, data.micText)
        compare(findChild(popup, "speakerVolumeValue").text, "54%")
    }

    function test_volume_height_stable_across_profiles() {
        popup.state = "a2dp"
        wait(50)
        var panel = findChild(popup, "volumePanel")
        var h = panel.height
        var testY = findChild(popup, "micPanel").mapToItem(popup, 0, 0).y
        popup.state = "hfp"
        wait(50)
        compare(panel.height, h)
        compare(findChild(popup, "micPanel").mapToItem(popup, 0, 0).y, testY)
    }

    function test_volume_keyboard_and_wheel() {
        popup.state = "hfp"
        wait(50)
        var slider = findChild(popup, "speakerVolumeSlider")
        slider.forceActiveFocus()
        verify(slider.activeFocus)
        keyClick(Qt.Key_Right)
        compare(speakerVolumeSpy.count, 1)
        compare(speakerVolumeSpy.signalArguments[0][0], 59)
        // main.qml echoes the new level back through info (optimistic update).
        withInfo({speaker_volume: 59})
        wait(20)
        compare(findChild(popup, "speakerVolumeValue").text, "59%")
        keyClick(Qt.Key_Left)
        compare(speakerVolumeSpy.signalArguments[1][0], 54)
        var mic = findChild(popup, "micVolumeSlider")
        mouseWheel(mic, mic.width / 2, mic.height / 2, 0, 120)
        verify(micVolumeSpy.count >= 1, "Wheel should change the mic level")
        compare(speakerVolumeSpy.count, 2)
    }

    function test_volume_drag_sends_levels() {
        popup.state = "a2dp"
        wait(50)
        var slider = findChild(popup, "speakerVolumeSlider")
        mouseClick(slider, slider.width - 2, slider.height / 2)
        verify(speakerVolumeSpy.count >= 1)
        var last = speakerVolumeSpy.signalArguments[speakerVolumeSpy.count - 1][0]
        verify(last >= 95 && last <= 100, "Click near the end should be ~100, got " + last)
    }

    function test_volume_mute_toggle() {
        popup.state = "hfp"
        wait(50)
        mouseClick(findChild(popup, "speakerVolumeMute"))
        compare(speakerMuteSpy.count, 1)
        compare(speakerMuteSpy.signalArguments[0][0], true)
        withInfo({speaker_muted: true})
        wait(50)
        compare(findChild(popup, "speakerVolumeValue").text, "Muted")
        compare(findChild(popup, "speakerVolumeSlider").value, 54)
        mouseClick(findChild(popup, "speakerVolumeMute"))
        compare(speakerMuteSpy.signalArguments[1][0], false)
        mouseClick(findChild(popup, "micVolumeMute"))
        compare(micMuteSpy.count, 1)
    }

    function test_volume_mic_locked_in_music() {
        popup.state = "a2dp"
        wait(50)
        mouseClick(findChild(popup, "micVolumeMute"))
        var mic = findChild(popup, "micVolumeSlider")
        mouseClick(mic, mic.width / 2, mic.height / 2)
        compare(micMuteSpy.count, 0)
        compare(micVolumeSpy.count, 0)
    }

    function test_volume_busy_and_testing() {
        popup.state = "hfp"
        popup.busy = true
        wait(50)
        verify(!findChild(popup, "speakerVolumeSlider").enabled)
        verify(!findChild(popup, "micVolumeSlider").enabled)
        popup.busy = false
        popup.testing = true
        wait(50)
        verify(findChild(popup, "micVolumeSlider").enabled,
               "The mic stays adjustable during a test")
    }

    function test_volume_follows_info_but_not_mid_drag() {
        popup.state = "a2dp"
        wait(50)
        var slider = findChild(popup, "speakerVolumeSlider")
        withInfo({speaker_volume: 30})
        wait(50)
        compare(slider.value, 30)
        mousePress(slider, slider.width * 0.75, slider.height / 2)
        var held = slider.value
        withInfo({speaker_volume: 10})
        wait(50)
        compare(slider.value, held, "An info refresh must not yank the handle mid-drag")
        mouseRelease(slider, slider.width * 0.75, slider.height / 2)
        wait(50)
        compare(slider.value, 10)
    }

    function test_volume_unknown_level() {
        popup.state = "a2dp"
        withInfo({speaker_volume: null, speaker_muted: null})
        wait(50)
        compare(findChild(popup, "speakerVolumeValue").text, "Not available yet")
        verify(!findChild(popup, "speakerVolumeSlider").enabled)
        withInfo({speaker_volume: 130})
        wait(50)
        compare(findChild(popup, "speakerVolumeValue").text, "100%")
    }

    function test_volume_fits_width() {
        popup.state = "hfp"
        wait(50)
        var names = ["speakerVolumeSlider", "speakerVolumeValue", "micVolumeSlider", "micVolumeValue"]
        for (var i = 0; i < names.length; i++) {
            var item = findChild(popup, names[i])
            verify(item.mapToItem(popup, item.width, 0).x <= popup.width,
                   names[i] + " exceeds popup width")
        }
    }
}
