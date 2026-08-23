pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Polled resource usage service with RAM, Swap, CPU, GPU usage, temperatures,
 * and top processes. Customized for NVIDIA GPU + AMD CPU (k10temp).
 */
Singleton {
    id: root
	property real memoryTotal: 1
	property real memoryFree: 0
	property real memoryUsed: memoryTotal - memoryFree
    property real memoryUsedPercentage: memoryUsed / memoryTotal
    property real swapTotal: 1
	property real swapFree: 0
	property real swapUsed: swapTotal - swapFree
    property real swapUsedPercentage: swapTotal > 0 ? (swapUsed / swapTotal) : 0
    property real cpuUsage: 0
    property real cpuTemp: 0
    property real gpuUsage: 0
    property real gpuTemp: 0
    property real cpuPower: 0
    property real gpuPower: 0
    property real totalPower: cpuPower + gpuPower
    property var previousCpuStats
    property real previousRaplEnergy: -1
    property real previousRaplTimestamp: 0
    property var topCpuProcesses: []
    property var topMemProcesses: []
    // Counts open popups showing the process lists; the ps probes only run
    // while nonzero (same pattern as ResourceHistory.consumers)
    property int detailConsumers: 0
    onDetailConsumersChanged: {
        if (detailConsumers > 0) {
            topProcsProc.running = false; topProcsProc.running = true
        }
    }

    property string maxAvailableMemoryString: kbToGbString(ResourceUsage.memoryTotal)
    property string maxAvailableSwapString: kbToGbString(ResourceUsage.swapTotal)
    property string maxAvailableCpuString: "--"

    readonly property int historyLength: Config?.options.resources.historyLength ?? 60
    property list<real> cpuUsageHistory: []
    property list<real> memoryUsageHistory: []
    property list<real> swapUsageHistory: []

    function kbToGbString(kb) {
        return (kb / (1024 * 1024)).toFixed(1) + " GB";
    }

    function updateMemoryUsageHistory() {
        memoryUsageHistory = [...memoryUsageHistory, memoryUsedPercentage]
        if (memoryUsageHistory.length > historyLength) {
            memoryUsageHistory.shift()
        }
    }
    function updateSwapUsageHistory() {
        swapUsageHistory = [...swapUsageHistory, swapUsedPercentage]
        if (swapUsageHistory.length > historyLength) {
            swapUsageHistory.shift()
        }
    }
    function updateCpuUsageHistory() {
        cpuUsageHistory = [...cpuUsageHistory, cpuUsage]
        if (cpuUsageHistory.length > historyLength) {
            cpuUsageHistory.shift()
        }
    }
    function updateHistories() {
        updateMemoryUsageHistory()
        updateSwapUsageHistory()
        updateCpuUsageHistory()
    }

	Timer {
		interval: 1
        running: true
        repeat: true
		onTriggered: {
            fileMeminfo.reload()
            fileStat.reload()

            const textMeminfo = fileMeminfo.text()
            memoryTotal = Number(textMeminfo.match(/MemTotal: *(\d+)/)?.[1] ?? 1)
            memoryFree = Number(textMeminfo.match(/MemAvailable: *(\d+)/)?.[1] ?? 0)
            swapTotal = Number(textMeminfo.match(/SwapTotal: *(\d+)/)?.[1] ?? 1)
            swapFree = Number(textMeminfo.match(/SwapFree: *(\d+)/)?.[1] ?? 0)

            const textStat = fileStat.text()
            const cpuLine = textStat.match(/^cpu\s+(.+)/)
            if (cpuLine) {
                // user nice system idle iowait irq softirq steal (guest/guest_nice
                // are already included in user/nice, so stop at 8 fields).
                // iowait counts as idle, matching top/btop — treating it as busy
                // wildly overstates usage whenever the system waits on disk.
                const stats = cpuLine[1].trim().split(/\s+/).slice(0, 8).map(Number)
                const total = stats.reduce((a, b) => a + b, 0)
                const idle = stats[3] + (stats[4] ?? 0)

                if (previousCpuStats) {
                    const totalDiff = total - previousCpuStats.total
                    const idleDiff = idle - previousCpuStats.idle
                    cpuUsage = totalDiff > 0 ? (1 - idleDiff / totalDiff) : 0
                }

                previousCpuStats = { total, idle }
            }

            // Re-trigger external probes (process lists only while a popup shows them)
            raplProc.running = false; raplProc.running = true
            cpuTempProc.running = false; cpuTempProc.running = true
            gpuStatsProc.running = false; gpuStatsProc.running = true
            if (root.detailConsumers > 0) {
                topProcsProc.running = false; topProcsProc.running = true
            }

            root.updateHistories()
            interval = Config.options?.resources?.updateInterval ?? 3000
        }
	}

	FileView { id: fileMeminfo; path: "/proc/meminfo" }
    FileView { id: fileStat; path: "/proc/stat" }

    Process {
        id: findCpuMaxFreqProc
        environment: ({ LANG: "C", LC_ALL: "C" })
        command: ["bash", "-c", "lscpu | grep 'CPU max MHz' | awk '{print $4}'"]
        running: true
        stdout: StdioCollector {
            id: outputCollector
            onStreamFinished: {
                root.maxAvailableCpuString = (parseFloat(outputCollector.text) / 1000).toFixed(0) + " GHz"
            }
        }
    }

    // CPU package power via RAPL
    Process {
        id: raplProc
        environment: ({ LANG: "C", LC_ALL: "C" })
        command: ["sudo", "-n", "/usr/bin/rapl-read"]
        stdout: StdioCollector {
            onStreamFinished: {
                // Skip failed/garbage reads: an unguarded 0/NaN would poison
                // previousRaplEnergy and spike the next delta to absurd watts
                const text = this.text.trim()
                const raplUj = Number(text)
                if (text === "" || !isFinite(raplUj) || raplUj < 0) return
                const nowMs = Date.now()
                // On counter wraparound (raplUj < previous) the true delta is
                // unknowable (rapl-read exposes no max range): skip the sample
                if (root.previousRaplEnergy >= 0 && raplUj >= root.previousRaplEnergy && nowMs > root.previousRaplTimestamp) {
                    const deltaUj = raplUj - root.previousRaplEnergy
                    const deltaSec = (nowMs - root.previousRaplTimestamp) / 1000
                    if (deltaSec > 0) root.cpuPower = (deltaUj / 1e6) / deltaSec
                }
                root.previousRaplEnergy = raplUj
                root.previousRaplTimestamp = nowMs
            }
        }
    }

    // CPU temp via k10temp Tctl
    Process {
        id: cpuTempProc
        environment: ({ LANG: "C", LC_ALL: "C" })
        command: ["bash", "-c", "sensors -u k10temp-pci-00c3 2>/dev/null | awk '/Tctl:/{getline; print $2; exit}'"]
        stdout: StdioCollector {
            onStreamFinished: {
                const v = parseFloat(this.text)
                if (!isNaN(v)) root.cpuTemp = v
            }
        }
    }

    // GPU usage + temp via nvidia-smi
    Process {
        id: gpuStatsProc
        environment: ({ LANG: "C", LC_ALL: "C" })
        command: ["bash", "-c", "nvidia-smi --query-gpu=utilization.gpu,temperature.gpu,power.draw --format=csv,noheader,nounits 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = this.text.trim().split(",").map(s => parseFloat(s.trim()))
                if (parts.length >= 3 && !isNaN(parts[0]) && !isNaN(parts[1])) {
                    root.gpuUsage = parts[0] / 100
                    root.gpuTemp = parts[1]
                    if (!isNaN(parts[2])) root.gpuPower = parts[2]
                }
            }
        }
    }

    // Top 5 CPU- and memory-hungry processes from a single table scan
    Process {
        id: topProcsProc
        environment: ({ LANG: "C", LC_ALL: "C" })
        command: ["ps", "-eo", "comm,%cpu,%mem", "--no-headers"]
        stdout: StdioCollector {
            onStreamFinished: {
                const rows = this.text.trim().split("\n").map(line => {
                    const m = line.trim().match(/^(.+)\s+([\d.]+)\s+([\d.]+)$/)
                    return m ? { name: m[1].trim(), cpu: parseFloat(m[2]), mem: parseFloat(m[3]) } : null
                }).filter(x => x !== null)
                root.topCpuProcesses = rows.slice().sort((a, b) => b.cpu - a.cpu).slice(0, 5)
                    .map(r => ({ name: r.name, usage: r.cpu.toFixed(1) + "%" }))
                root.topMemProcesses = rows.slice().sort((a, b) => b.mem - a.mem).slice(0, 5)
                    .map(r => ({ name: r.name, mem: r.mem.toFixed(1) + "%" }))
            }
        }
    }
}
