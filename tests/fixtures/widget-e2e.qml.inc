    // Loaded only in the isolated test package.
    property int e2eStep: 0
    property bool e2eActionStarted: false
    property bool e2eSawWaveform: false

    function e2eFail(reason) {
        console.error("XM_E2E_FAIL step " + e2eStep + ": " + reason)
        e2eTimer.stop()
    }

    Timer {
        id: e2eTimer
        interval: 25
        repeat: true
        running: true
        onTriggered: {
            var view = root.fullRepresentationItem
            if (!view || !view.testPopup)
                return
            var popup = view.testPopup
            var steps = [
                [function () {}, function () { return root.info.device === "Fixture headset" && !root.pending }],
                [function () {
                    root.refreshInfo()
                    var snapshot = root.pending
                    root.refreshInfo()
                    root.refreshStatus()
                    if (!snapshot || root.pending !== snapshot)
                        root.e2eFail("background polling replaced the active snapshot")
                }, function () { return !root.pending }],
                [function () { popup.callRequested() }, function () { return root.info.state === "hfp" && !root.pending }],
                [function () {
                    for (var n = 20; n <= 60; n++)
                        popup.volumeRequested("speaker", n)
                    popup.volumeRequested("mic", 35)
                    popup.muteRequested("speaker", true)
                }, function () { return !root.volumeInFlight() && !root.pending }],
                [function () { popup.musicRequested() }, function () { return root.info.state === "a2dp" && !root.pending }],
                [function () { popup.testRequested() }, function () {
                    if (root.testing && root.liveLevels.length > 0)
                        root.e2eSawWaveform = true
                    if (!root.testResult)
                        return false
                    if (!root.e2eSawWaveform || root.testResult.verdict !== "live") {
                        root.e2eFail("missing waveform or verdict")
                        return false
                    }
                    return !root.pending
                }],
                [function () { popup.connectionRequested() }, function () { return root.info.state === "none" && !root.pending }],
                [function () { popup.connectionRequested() }, function () { return root.info.state === "a2dp" && !root.pending }],
                [function () { popup.reconnectRequested() }, function () { return root.message === "Headset link reset." && !root.pending }],
                [function () { popup.fixRequested() }, function () { return root.info.state === "hfp" && !root.pending }],
                [function () { popup.restoreRequested() }, function () { return root.confirmVisible }],
                [function () { popup.confirmCancelled() }, function () { return !root.confirmVisible }],
                [function () { popup.restoreRequested() }, function () { return root.confirmVisible }],
                [function () { popup.confirmAccepted() }, function () {
                    return root.message === "WirePlumber defaults restored." && !root.pending
                }],
                [function () { popup.volumeRequested("speaker", 99) }, function () {
                    return root.message === "Fixture volume failure" && !root.volumeInFlight() && !root.pending
                        && root.info.speaker_volume === 60
                }]
            ]
            if (root.e2eStep === steps.length) {
                console.log("XM_E2E_PASS")
                stop()
                return
            }
            var step = steps[root.e2eStep]
            if (!root.e2eActionStarted) {
                root.e2eActionStarted = true
                console.log("XM_E2E_STEP", root.e2eStep)
                step[0]()
            }
            if (step[1]()) {
                root.e2eStep++
                root.e2eActionStarted = false
            }
        }
    }
