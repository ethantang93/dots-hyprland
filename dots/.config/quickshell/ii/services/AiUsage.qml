pragma Singleton

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

/*
 * Claude / Codex plan usage, from scripts/ai-usage/ai-usage.sh.
 * Accounts are configured at the top of that script.
 */
Singleton {
    id: root

    readonly property int pollInterval: 2 * 60 * 1000
    property var accounts: [] // Only accounts that have credentials
    property int updatedAt: 0
    // Ticks every 30s so reset countdowns and pace markers move between polls
    property real now: Date.now() / 1000

    function load() {}
    function refresh(force) {
        if (fetchProc.running) return;
        fetchProc.command = ["bash", FileUtils.trimFileProtocol(`${Directories.scriptPath}/ai-usage/ai-usage.sh`)].concat(force ? ["--force"] : []);
        fetchProc.running = true;
    }

    // Window with the reset already applied if it has passed since the last fetch
    function effectiveUsed(win) {
        if (win.resetsAt && win.resetsAt <= root.now) return 0;
        return win.used ?? 0;
    }
    // 0..1 of the window that has elapsed
    function elapsedFraction(win) {
        if (!win.resetsAt || !win.windowSeconds) return 0;
        const remaining = win.resetsAt - root.now;
        if (remaining <= 0) return 0;
        return Math.max(0, Math.min(1, 1 - remaining / win.windowSeconds));
    }
    // Percentage points above (+) or below (-) an even pace through the window
    function paceDelta(win) {
        return root.effectiveUsed(win) - root.elapsedFraction(win) * 100;
    }
    // Fill color for a usage meter: primary under pace, tertiary ahead, error when burning hard
    function usageColor(used, elapsed) {
        const delta = used - elapsed * 100;
        if (used >= 90 || delta > 15) return Appearance.m3colors.m3error;
        if (delta >= 1) return Appearance.m3colors.m3tertiary;
        return Appearance.colors.colPrimary;
    }
    function formatDuration(seconds) {
        if (seconds <= 0) return Translation.tr("now");
        const d = Math.floor(seconds / 86400);
        const h = Math.floor((seconds % 86400) / 3600);
        const m = Math.floor((seconds % 3600) / 60);
        if (d > 0) return `${d}d ${h}h`;
        if (h > 0) return `${h}h ${m}m`;
        return `${m}m`;
    }
    function resetsIn(win) {
        if (!win.resetsAt) return "";
        return root.formatDuration(win.resetsAt - root.now);
    }

    Timer {
        interval: root.pollInterval
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.refresh(false)
    }

    Timer {
        interval: 30 * 1000
        repeat: true
        running: true
        onTriggered: root.now = Date.now() / 1000
    }

    Process {
        id: fetchProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text);
                    root.accounts = data.accounts.filter(a => a.status !== "missing");
                    root.updatedAt = data.updatedAt;
                    root.now = Date.now() / 1000;
                } catch (e) {
                    console.warn("[AiUsage] Bad script output:", e, text);
                }
            }
        }
    }
}
