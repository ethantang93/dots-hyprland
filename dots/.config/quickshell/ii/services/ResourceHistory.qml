pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Historical CPU/MEM usage for the IStat popup charts. Data is recorded by
 * the resource-history daemon (systemd user unit) into a tiered ring-buffer
 * file; this service only runs its `query` CLI, which returns the ~120
 * downsampled points for the selected window. Marked active while a chart
 * is on screen so refreshes only happen when needed.
 */
Singleton {
    id: root

    property int windowSeconds: 3600
    // Counted, not boolean: when switching popups the new chart can be
    // created before the old one is destroyed, and a boolean would end false
    property int consumers: 0
    readonly property bool active: consumers > 0

    // Values 0-1; -1 marks a gap (no data recorded for that bucket)
    property list<real> cpuHistory: []
    property list<real> cpuMaxHistory: []
    property list<real> memHistory: []
    property list<real> memMaxHistory: []
    property int bucketSeconds: 30

    function refresh() {
        queryProc.running = false;
        // Set imperatively: a binding on `command` may not have re-evaluated
        // yet when this runs from onWindowSecondsChanged, so the process
        // would relaunch with the previous window's query
        queryProc.command = [
            "/usr/bin/resource-history",
            "query", "--window", root.windowSeconds.toString()
        ];
        queryProc.running = true;
    }

    onActiveChanged: if (active) refresh()
    onWindowSecondsChanged: if (active) refresh()

    Timer {
        interval: 60000
        running: root.active
        repeat: true
        onTriggered: root.refresh()
    }

    Process {
        id: queryProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(this.text);
                    root.cpuHistory = data.cpu;
                    root.cpuMaxHistory = data.cpuMax;
                    root.memHistory = data.mem;
                    root.memMaxHistory = data.memMax;
                    root.bucketSeconds = data.bucketSeconds;
                } catch (e) {
                    console.log("[ResourceHistory] failed to parse query output: " + e);
                }
            }
        }
    }
}
