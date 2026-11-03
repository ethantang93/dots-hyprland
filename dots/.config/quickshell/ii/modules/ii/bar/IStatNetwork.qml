import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

/**
 * iStat Menus-style network readout: upload over download, in fixed-width
 * number/unit slots so the bar doesn't shift as the digits change. Click
 * opens the detail popup (coordinated by IStatWidget like the gauges).
 */
MouseArea {
    id: root

    // Fixed iStat palette, like the gauges: not theme-driven on purpose
    readonly property color downloadColor: "#22D3EE"
    readonly property color uploadColor: "#FB923C"

    property bool expanded: false
    signal toggleRequested()
    signal dismissRequested()

    onClicked: root.toggleRequested()

    // Probe connection details only while the popup is open. This can't
    // live in the popup content's onCompleted: StyledPopup takes its content
    // as an Item, so that is created with the bar, not when the popup opens.
    onExpandedChanged: NetworkTraffic.infoConsumers += root.expanded ? 1 : -1
    Component.onDestruction: if (root.expanded) NetworkTraffic.infoConsumers--

    implicitWidth: rates.implicitWidth
    implicitHeight: rates.implicitHeight

    component RateRow: Row {
        id: row
        required property real rate
        required property string icon
        required property color arrowColor
        readonly property var formatted: NetworkTraffic.formatRate(row.rate)
        spacing: 1

        TextMetrics {
            id: numberMetrics
            font: numberText.font
            text: "888"
        }
        TextMetrics {
            id: unitMetrics
            font: unitText.font
            text: "MB/s"
        }

        MaterialSymbol {
            anchors.verticalCenter: parent.verticalCenter
            text: row.icon
            iconSize: 9
            fill: 1
            color: row.arrowColor
        }
        StyledText {
            id: numberText
            anchors.verticalCenter: parent.verticalCenter
            width: Math.ceil(numberMetrics.advanceWidth)
            horizontalAlignment: Text.AlignRight
            shouldUseNumberFont: true // keep one font as values flip between "12" and "1.2"
            text: row.formatted.value
            font.pixelSize: 9
            font.weight: Font.Bold
            color: Appearance.colors.colOnLayer1
        }
        StyledText {
            id: unitText
            anchors.verticalCenter: parent.verticalCenter
            width: Math.ceil(unitMetrics.advanceWidth) + 1
            text: row.formatted.unit
            font.pixelSize: 8
            color: Appearance.colors.colSubtext
        }
    }

    Column {
        id: rates
        anchors.centerIn: parent
        spacing: -2

        RateRow {
            rate: NetworkTraffic.uploadRate
            icon: "arrow_upward"
            arrowColor: root.uploadColor
        }
        RateRow {
            rate: NetworkTraffic.downloadRate
            icon: "arrow_downward"
            arrowColor: root.downloadColor
        }
    }

    StyledPopup {
        hoverTarget: root
        active: root.expanded
        dismissOnOutsideClick: true
        onDismissed: root.dismissRequested()

        IStatNetworkSection {
            anchors.centerIn: parent
            downloadColor: root.downloadColor
            uploadColor: root.uploadColor
        }
    }
}
