pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Network throughput for the iStat-style bar readout, from /proc/net/dev.
 * Rates are summed over interfaces backed by real hardware only: bridges,
 * bonds, VPN tunnels (WARP, WireGuard...), containers and loopback carry
 * traffic that is already counted on a physical link, or none at all.
 * Polled every second: a plain /proc read, no subprocess.
 *
 * Connection details (interface, IP, router, Wi-Fi link) are probed only
 * while a popup that shows them is open (`infoConsumers`, same pattern as
 * ResourceUsage.detailConsumers). Wi-Fi details come from NetworkManager;
 * signal strength is read from /proc/net/wireless.
 */
Singleton {
    id: root

    readonly property int pollInterval: 1000
    readonly property int historyLength: 120 // 2 minutes at 1 s

    property real downloadRate: 0 // bytes/s
    property real uploadRate: 0
    property real totalReceived: 0 // bytes since the interfaces came up
    property real totalSent: 0
    property list<real> downloadHistory: []
    property list<real> uploadHistory: []
    readonly property real downloadPeak: downloadHistory.reduce((a, b) => Math.max(a, b), 0)
    readonly property real uploadPeak: uploadHistory.reduce((a, b) => Math.max(a, b), 0)

    // { iface, type: "wifi"|"ethernet"|"", ipv4, gateway, ssid, rssi,
    //   channel, frequency, security, txBitrate (Mb/s), linkSpeed (Mb/s) }
    property var info: ({})
    // Counted, not boolean: popups can overlap briefly while switching
    property int infoConsumers: 0
    onInfoConsumersChanged: if (infoConsumers > 0 && !infoProc.running) infoProc.running = true

    // Per-interface counters from the previous sample: { name: { rx, tx } }
    property var previousCounters: null
    property real previousTimestamp: 0

    // Interfaces with a /sys/class/net/<if>/device link, i.e. real hardware.
    // Refreshed whenever the set of interface names in /proc/net/dev changes.
    property var physicalInterfaces: ({})
    property string interfaceSetKey: ""

    // Decimal units (network convention); number and unit come back split
    // so the bar can lay them out in fixed-width slots
    function formatRate(bytesPerSec) {
        const kb = Math.max(0, bytesPerSec) / 1000;
        if (kb < 999.5) return { value: Math.round(kb).toString(), unit: "KB/s" };
        const mb = kb / 1000;
        if (mb < 9.95) return { value: mb.toFixed(1), unit: "MB/s" };
        if (mb < 999.5) return { value: Math.round(mb).toString(), unit: "MB/s" };
        const gb = mb / 1000;
        return { value: gb < 9.95 ? gb.toFixed(1) : Math.round(gb).toString(), unit: "GB/s" };
    }
    function formatRateString(bytesPerSec) {
        const r = formatRate(bytesPerSec);
        return r.value + " " + r.unit;
    }
    function formatBytes(bytes) {
        const units = ["B", "KB", "MB", "GB", "TB"];
        let v = Math.max(0, bytes);
        let i = 0;
        // Compare against the rounding thresholds, not 1000/100, so 999.96 MB
        // shows as "1.0 GB" rather than "1000 MB"
        while (v >= 999.5 && i < units.length - 1) {
            v /= 1000;
            i++;
        }
        return (i === 0 || v >= 99.95 ? Math.round(v) : v.toFixed(1)) + " " + units[i];
    }

    function pushHistory(history, value) {
        const next = [...history, value];
        if (next.length > historyLength) next.shift();
        return next;
    }

    function sample() {
        const text = netDevFile.text();
        const now = Date.now();
        const counters = {};
        const names = [];
        let totalRx = 0;
        let totalTx = 0;
        // Skip the two header lines; each row is "iface: rx_bytes ... (8 rx
        // fields) tx_bytes ..."
        for (const line of text.split("\n").slice(2)) {
            const m = line.match(/^\s*([^:\s]+):\s*(.*)$/);
            if (!m) continue;
            names.push(m[1]);
            if (!root.physicalInterfaces[m[1]]) continue;
            const fields = m[2].trim().split(/\s+/).map(Number);
            if (fields.length < 9 || !isFinite(fields[0]) || !isFinite(fields[8])) continue;
            counters[m[1]] = { rx: fields[0], tx: fields[8] };
            totalRx += fields[0];
            totalTx += fields[8];
        }

        // Interfaces came or went (boot, hotplug, VPN up/down): re-check which
        // ones are physical. Restarting covers a change while a check runs.
        const interfaceSetKey = names.join(" ");
        if (interfaceSetKey !== root.interfaceSetKey) {
            root.interfaceSetKey = interfaceSetKey;
            physicalProc.running = false;
            physicalProc.running = true;
        }

        // TX/RX counters advance in bursts as packets are queued, so a very
        // short interval (timer jitter, startup load) inflates a burst into an
        // impossible rate. Keep the old baseline and let the next tick cover
        // a full interval instead.
        const elapsed = now - root.previousTimestamp;
        if (root.previousCounters && elapsed >= 0 && elapsed < root.pollInterval / 2) {
            root.totalReceived = totalRx;
            root.totalSent = totalTx;
            return;
        }

        // A negative interval means the wall clock stepped back (NTP, an RTC
        // kept in local time): no valid rate, so this sample just becomes the
        // new baseline instead of freezing until the clock catches up
        if (root.previousCounters && elapsed >= 0) {
            let rxDelta = 0;
            let txDelta = 0;
            for (const name in counters) {
                const prev = root.previousCounters[name];
                // New interface or counters reset (link recreated): no
                // baseline, so it contributes nothing to this sample
                if (!prev) continue;
                if (counters[name].rx >= prev.rx) rxDelta += counters[name].rx - prev.rx;
                if (counters[name].tx >= prev.tx) txDelta += counters[name].tx - prev.tx;
            }
            const seconds = elapsed / 1000;
            root.downloadRate = rxDelta / seconds;
            root.uploadRate = txDelta / seconds;
            root.downloadHistory = root.pushHistory(root.downloadHistory, root.downloadRate);
            root.uploadHistory = root.pushHistory(root.uploadHistory, root.uploadRate);
        }

        root.previousCounters = counters;
        root.previousTimestamp = now;
        root.totalReceived = totalRx;
        root.totalSent = totalTx;
    }

    Timer {
        interval: root.pollInterval
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            netDevFile.reload();
            root.sample();
        }
    }

    // Refresh connection details while a popup shows them (signal strength
    // and bitrate drift; the default route can change under us)
    Timer {
        interval: 5000
        running: root.infoConsumers > 0
        repeat: true
        onTriggered: if (!infoProc.running) infoProc.running = true
    }

    FileView {
        id: netDevFile
        path: "/proc/net/dev"
        // text() right after reload() must return the fresh counters, not
        // the previous read: a stale read would pair old bytes with a new
        // timestamp and skew every rate
        blockAllReads: true
    }

    Process {
        id: physicalProc
        command: ["sh", "-c", "for d in /sys/class/net/*; do [ -e \"$d/device\" ] && echo \"${d##*/}\"; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                const physical = {};
                for (const name of this.text.split("\n")) {
                    if (name.trim()) physical[name.trim()] = true;
                }
                root.physicalInterfaces = physical;
            }
        }
    }

    Process {
        id: infoProc
        environment: ({ LANG: "C", LC_ALL: "C" })
        command: ["bash", "-c", `
            # First default route on real hardware (same rule as the rates):
            # VPN tunnels like WARP may also install one, but the details
            # shown are for the physical link underneath
            dev=
            for d in $(ip route show default 2>/dev/null | awk '{for (i = 1; i < NF; i++) if ($i == "dev") print $(i + 1)}'); do
                if [ -e "/sys/class/net/$d/device" ]; then dev=$d; break; fi
            done
            [ -n "$dev" ] || exit 0
            echo "iface=$dev"
            ip route show default dev "$dev" 2>/dev/null | awk '{for (i = 1; i < NF; i++) if ($i == "via") { print "gateway=" $(i + 1); exit }}'
            ip -4 -o addr show dev "$dev" 2>/dev/null | awk '{ sub(/\\/.*/, "", $4); print "ipv4=" $4; exit }'
            if [ -d "/sys/class/net/$dev/wireless" ]; then
                echo "type=wifi"
                # Signal (dBm) straight from the kernel
                awk -v d="$dev:" '$1 == d { sub(/\\.$/, "", $4); print "rssi=" $4 }' /proc/net/wireless
                # Active AP as IN-USE:SSID:CHAN:FREQ:SECURITY (SSID colons arrive escaped)
                echo "nmWifi=$(nmcli -g IN-USE,SSID,CHAN,FREQ,SECURITY device wifi list ifname "$dev" --rescan no 2>/dev/null | grep -m1 '^\\*')"
                # The current TX bitrate (Kbit/s) is only exposed over D-Bus
                path=$(nmcli -g GENERAL.DBUS-PATH device show "$dev" 2>/dev/null)
                [ -n "$path" ] && busctl get-property org.freedesktop.NetworkManager "$path" \\
                    org.freedesktop.NetworkManager.Device.Wireless Bitrate 2>/dev/null | awk '{ print "txBitrate=" $2 }'
            else
                echo "type=ethernet"
                echo "linkSpeed=$(cat "/sys/class/net/$dev/speed" 2>/dev/null)"
            fi
        `]
        stdout: StdioCollector {
            onStreamFinished: {
                const result = {};
                for (const line of this.text.split("\n")) {
                    const kv = line.match(/^(\w+)=(.*)$/);
                    if (kv) result[kv[1]] = kv[2].trim();
                }
                // nmcli -g row: IN-USE:SSID:CHAN:FREQ:SECURITY, with ":" and
                // "\" inside values escaped by a backslash
                if (result.nmWifi) {
                    const fields = [];
                    let current = "";
                    for (let c = 0; c < result.nmWifi.length; c++) {
                        const ch = result.nmWifi[c];
                        if (ch === "\\" && c + 1 < result.nmWifi.length) current += result.nmWifi[++c];
                        else if (ch === ":") { fields.push(current); current = ""; }
                        else current += ch;
                    }
                    fields.push(current);
                    if (fields[1]) result.ssid = fields[1];
                    if (fields[2]) result.channel = fields[2];
                    if (fields[3]) result.frequency = parseInt(fields[3]);
                    if (fields[4]) result.security = fields[4];
                }
                delete result.nmWifi;
                // Normalize: dBm as a number, bitrate (Kbit/s) as Mbit/s
                if (result.rssi) result.rssi = parseInt(result.rssi);
                if (result.txBitrate) result.txBitrate = Math.round(parseInt(result.txBitrate) / 1000);
                // /sys reports -1 / errors for links without a negotiated speed
                if (result.linkSpeed !== undefined) {
                    const speed = parseInt(result.linkSpeed);
                    result.linkSpeed = speed > 0 ? speed : undefined;
                }
                root.info = result;
            }
        }
    }
}
