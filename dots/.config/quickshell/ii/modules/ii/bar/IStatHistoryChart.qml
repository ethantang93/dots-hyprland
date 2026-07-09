import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import QtQuick
import QtQuick.Layouts

/**
 * Usage-history section for the IStat popups: 1h/6h/12h/1d range picker over
 * a ~120-point line chart. Data comes from the ResourceHistory service
 * (resource-history daemon); the service is marked active while this exists,
 * which the LazyLoader'd popup guarantees matches popup visibility.
 */
ColumnLayout {
    id: chart
    required property color accentColor
    required property string metricId // "cpu" | "mem"
    property int chartWidth: 240

    readonly property var ranges: [
        { label: "1h", secs: 3600 },
        { label: "6h", secs: 21600 },
        { label: "12h", secs: 43200 },
        { label: "1d", secs: 86400 },
    ]

    spacing: 6

    Component.onCompleted: ResourceHistory.consumers++
    Component.onDestruction: ResourceHistory.consumers--

    // Range picker
    Row {
        Layout.alignment: Qt.AlignHCenter
        spacing: 4

        Repeater {
            model: chart.ranges

            Rectangle {
                id: pill
                required property var modelData
                readonly property bool selected: ResourceHistory.windowSeconds === pill.modelData.secs
                width: 36
                height: 18
                radius: 9
                color: pill.selected ? ColorUtils.transparentize(chart.accentColor, 0.7) : "transparent"

                StyledText {
                    anchors.centerIn: parent
                    text: pill.modelData.label
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: pill.selected ? Font.DemiBold : Font.Normal
                    color: pill.selected ? Appearance.colors.colOnLayer1 : Appearance.colors.colSubtext
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: ResourceHistory.windowSeconds = pill.modelData.secs
                }
            }
        }
    }

    // Chart
    Rectangle {
        Layout.alignment: Qt.AlignHCenter
        implicitWidth: chart.chartWidth
        implicitHeight: 70
        radius: Appearance.rounding.verysmall
        color: Appearance.colors.colLayer2
        border.width: 1
        border.color: Appearance.colors.colOutlineVariant
        clip: true

        Graph {
            anchors.fill: parent
            anchors.margins: 1
            values: chart.metricId === "mem" ? ResourceHistory.memHistory : ResourceHistory.cpuHistory
            color: chart.accentColor
            fillOpacity: 0.35
            alignment: Graph.Alignment.Right
        }
    }
}
