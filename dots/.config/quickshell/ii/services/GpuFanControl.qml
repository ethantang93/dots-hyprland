pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

/**
 * NVIDIA GPU fan control via nvidia-settings.
 * Toggles GPUFanControlState (auto/manual) and sets GPUTargetFanSpeed.
 * Polls actual fan speed periodically so the UI can reflect current state.
 */
Singleton {
    id: root

    property bool manual: false
    property int targetSpeed: 50
    property int currentSpeed: 0
    property int minSpeed: 27
    property int maxSpeed: 100
    property bool ready: false

    function setManual(enabled) {
        if (enabled) {
            const speed = Math.max(root.minSpeed, Math.min(root.maxSpeed, Math.round(root.targetSpeed)));
            Quickshell.execDetached(["sudo", "-n", "/usr/local/bin/gpu-fan", "manual", `${speed}`]);
        } else {
            Quickshell.execDetached(["sudo", "-n", "/usr/local/bin/gpu-fan", "auto"]);
        }
        root.manual = enabled;
        refreshTimer.restart();
    }

    function setSpeed(speed) {
        const clamped = Math.max(root.minSpeed, Math.min(root.maxSpeed, Math.round(speed)));
        root.targetSpeed = clamped;
        if (root.manual) {
            Quickshell.execDetached(["sudo", "-n", "/usr/local/bin/gpu-fan", "speed", `${clamped}`]);
            refreshTimer.restart();
        }
    }

    function refresh() {
        stateProc.running = true;
    }

    Timer {
        id: pollTimer
        interval: 3000
        running: true
        repeat: true
        onTriggered: root.refresh()
    }

    Timer {
        id: refreshTimer
        interval: 1500
        repeat: false
        onTriggered: root.refresh()
    }

    Process {
        id: stateProc
        command: ["sudo", "-n", "/usr/local/bin/gpu-fan", "query"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n").map(l => l.trim()).filter(l => l.length > 0);
                if (lines.length < 3) return;
                const state = parseInt(lines[0]);
                const current = parseInt(lines[1]);
                const target = parseInt(lines[2]);
                if (!isNaN(state)) root.manual = (state === 1);
                if (!isNaN(current)) root.currentSpeed = current;
                if (!isNaN(target) && !root.ready) {
                    root.targetSpeed = Math.max(root.minSpeed, target);
                }
                root.ready = true;
            }
        }
    }

    Component.onCompleted: refresh()
}
