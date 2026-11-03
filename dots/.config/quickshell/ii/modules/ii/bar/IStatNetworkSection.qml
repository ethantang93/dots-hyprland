import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

/**
 * Network popup content (iStat Menus style): current rates, a mirrored
 * 2-minute history graph (download up, upload down, each half on its own
 * scale), connection details and since-boot totals.
 */
ColumnLayout {
    id: section
    required property color downloadColor
    required property color uploadColor
    // Same design width as the CPU/MEM popups
    readonly property int contentWidth: 240
    readonly property var info: NetworkTraffic.info

    spacing: 8

    // Round a peak up to 1/2/5 × 10^n for the graph scale. The 100 KB/s
    // floor keeps idle background chatter from filling the whole graph
    function niceScale(peak) {
        const v = Math.max(peak, 100e3);
        const magnitude = Math.pow(10, Math.floor(Math.log10(v)));
        for (const m of [1, 2, 5]) {
            if (v <= m * magnitude) return m * magnitude;
        }
        return 10 * magnitude;
    }
    readonly property real downloadScale: niceScale(NetworkTraffic.downloadPeak)
    readonly property real uploadScale: niceScale(NetworkTraffic.uploadPeak)

    function normalized(history, scale) {
        return history.map(v => Math.min(1, v / scale));
    }

    function signalQuality(dbm) {
        if (dbm >= -50) return "excellent";
        if (dbm >= -60) return "good";
        if (dbm >= -70) return "fair";
        return "weak";
    }
    function band(mhz) {
        if (!mhz) return "";
        if (mhz < 3000) return "2.4 GHz";
        if (mhz < 5925) return "5 GHz";
        return "6 GHz";
    }

    readonly property var connectionRows: {
        const i = section.info;
        const rows = [];
        if (i.iface) rows.push({ label: "Interface", value: i.iface });
        if (i.ipv4) rows.push({ label: "IP address", value: i.ipv4 });
        if (i.gateway) rows.push({ label: "Router", value: i.gateway });
        if (i.type === "wifi") {
            if (i.rssi !== undefined && !isNaN(i.rssi))
                rows.push({ label: "Signal", value: i.rssi + " dBm (" + section.signalQuality(i.rssi) + ")" });
            if (i.channel) {
                const b = section.band(parseInt(i.frequency));
                rows.push({ label: "Channel", value: i.channel + (b ? " · " + b : "") });
            }
            if (i.txBitrate) rows.push({ label: "Link rate", value: i.txBitrate + " Mb/s" });
            if (i.security) rows.push({ label: "Security", value: i.security });
        } else if (i.linkSpeed) {
            rows.push({ label: "Link speed", value: i.linkSpeed + " Mb/s" });
        }
        return rows;
    }

    component Separator: Rectangle {
        Layout.alignment: Qt.AlignHCenter
        implicitWidth: section.contentWidth
        implicitHeight: 1
        color: Appearance.colors.colOutlineVariant
    }

    component InfoRow: Item {
        id: infoRow
        required property string label
        required property string value
        implicitWidth: section.contentWidth
        implicitHeight: valueText.implicitHeight

        StyledText {
            id: labelText
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: infoRow.label
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colSubtext
        }
        StyledText {
            id: valueText
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, parent.width - labelText.implicitWidth - 12)
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideRight
            text: infoRow.value
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colOnLayer1
        }
    }

    component RateBlock: Item {
        id: rateBlock
        required property string label
        required property string icon
        required property color accent
        required property real rate
        // Fixed half-width slots so the popup doesn't shift as digits change
        implicitWidth: section.contentWidth / 2
        implicitHeight: rateColumn.implicitHeight

        Column {
            id: rateColumn
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: -2

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 2

                MaterialSymbol {
                    anchors.verticalCenter: parent.verticalCenter
                    text: rateBlock.icon
                    iconSize: Appearance.font.pixelSize.larger
                    fill: 1
                    color: rateBlock.accent
                }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: NetworkTraffic.formatRateString(rateBlock.rate)
                    font.pixelSize: Appearance.font.pixelSize.huge
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer1
                }
            }
            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: rateBlock.label
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
        }
    }

    // Header: connection type + name
    RowLayout {
        Layout.alignment: Qt.AlignHCenter
        Layout.topMargin: 4
        Layout.maximumWidth: section.contentWidth
        spacing: 6

        MaterialSymbol {
            text: section.info.type === "wifi" ? "wifi" : section.info.type === "ethernet" ? "lan" : "public"
            iconSize: Appearance.font.pixelSize.larger
            color: Appearance.colors.colOnLayer1
        }
        StyledText {
            Layout.fillWidth: true
            text: section.info.type === "wifi" ? (section.info.ssid || "Wi-Fi")
                : section.info.type === "ethernet" ? "Ethernet" : "Network"
            elide: Text.ElideRight
            font.pixelSize: Appearance.font.pixelSize.normal
            font.weight: Font.DemiBold
            color: Appearance.colors.colOnLayer1
        }
    }

    // Current rates
    RowLayout {
        Layout.alignment: Qt.AlignHCenter
        spacing: 0

        RateBlock {
            label: "Download"
            icon: "arrow_downward"
            accent: section.downloadColor
            rate: NetworkTraffic.downloadRate
        }
        RateBlock {
            label: "Upload"
            icon: "arrow_upward"
            accent: section.uploadColor
            rate: NetworkTraffic.uploadRate
        }
    }

    // Mirrored history graph: download grows up from the midline, upload down
    ColumnLayout {
        Layout.alignment: Qt.AlignHCenter
        spacing: 3

        Rectangle {
            id: chartFrame
            readonly property real halfHeight: (height - 2) / 2
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: section.contentWidth
            implicitHeight: 90
            radius: Appearance.rounding.verysmall
            color: Appearance.colors.colLayer2
            border.width: 1
            border.color: Appearance.colors.colOutlineVariant
            clip: true

            Graph {
                x: 1
                y: 1
                width: parent.width - 2
                height: chartFrame.halfHeight
                values: section.normalized(NetworkTraffic.downloadHistory, section.downloadScale)
                points: NetworkTraffic.historyLength
                color: section.downloadColor
                fillOpacity: 0.35
                alignment: Graph.Alignment.Right
            }
            Graph {
                id: uploadGraph
                x: 1
                y: 1 + chartFrame.halfHeight
                width: parent.width - 2
                height: chartFrame.halfHeight
                values: section.normalized(NetworkTraffic.uploadHistory, section.uploadScale)
                points: NetworkTraffic.historyLength
                color: section.uploadColor
                fillOpacity: 0.35
                alignment: Graph.Alignment.Right
                transform: Scale {
                    origin.y: uploadGraph.height / 2
                    yScale: -1
                }
            }
            Rectangle {
                x: 1
                y: 1 + chartFrame.halfHeight
                width: parent.width - 2
                height: 1
                color: Appearance.colors.colOutlineVariant
            }

            // Scale (full-height value) of each half
            StyledText {
                anchors { top: parent.top; left: parent.left; topMargin: 3; leftMargin: 5 }
                text: NetworkTraffic.formatRateString(section.downloadScale)
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colSubtext
            }
            StyledText {
                anchors { bottom: parent.bottom; left: parent.left; bottomMargin: 3; leftMargin: 5 }
                text: NetworkTraffic.formatRateString(section.uploadScale)
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colSubtext
            }
        }

        Item {
            implicitWidth: section.contentWidth
            implicitHeight: windowCaption.implicitHeight

            StyledText {
                id: windowCaption
                anchors.left: parent.left
                text: "Last 2 min"
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colSubtext
            }
            StyledText {
                anchors.right: parent.right
                text: "Peak ↓ " + NetworkTraffic.formatRateString(NetworkTraffic.downloadPeak)
                    + "   ↑ " + NetworkTraffic.formatRateString(NetworkTraffic.uploadPeak)
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colSubtext
            }
        }
    }

    // Connection details
    Separator {
        visible: section.connectionRows.length > 0
    }
    Column {
        Layout.alignment: Qt.AlignHCenter
        visible: section.connectionRows.length > 0
        spacing: 3

        Repeater {
            model: section.connectionRows

            InfoRow {
                required property var modelData
                label: modelData.label
                value: modelData.value
            }
        }
    }

    // Totals since the interfaces came up (≈ since boot)
    Separator {}
    Column {
        Layout.alignment: Qt.AlignHCenter
        Layout.bottomMargin: 2
        spacing: 3

        InfoRow {
            label: "Downloaded since boot"
            value: NetworkTraffic.formatBytes(NetworkTraffic.totalReceived)
        }
        InfoRow {
            label: "Uploaded since boot"
            value: NetworkTraffic.formatBytes(NetworkTraffic.totalSent)
        }
    }
}
