import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: section
    required property string title
    required property color gaugeColor
    required property real gaugeValue
    property var details: []
    property var processes: []
    property string processValueKey: "usage"
    property string metricId: ""
    property bool showHistory: false
    readonly property bool hasProcesses: section.processes && section.processes.length > 0
    // Single design width for the popup content; chart, dividers, and
    // process rows all derive from it so they stay aligned
    readonly property int contentWidth: 240
    readonly property int processRowSpacing: 12
    readonly property int processValueWidth: 78
    readonly property int processNameWidth: contentWidth - processValueWidth - processRowSpacing
    readonly property int processRowWidth: contentWidth

    spacing: 8

    // The ps probes feeding the process list only run while a popup that
    // shows one is open (GPU has no process list)
    readonly property bool consumesProcessList: metricId === "cpu" || metricId === "mem"
    Component.onCompleted: if (consumesProcessList) ResourceUsage.detailConsumers++
    Component.onDestruction: if (consumesProcessList) ResourceUsage.detailConsumers--

    // Ring gauge (iStat Menus style): % + metric name in the center
    Item {
        Layout.alignment: Qt.AlignHCenter
        Layout.topMargin: 4
        implicitWidth: 88
        implicitHeight: 88

        CircularProgress {
            anchors.fill: parent
            implicitSize: 88
            lineWidth: 7
            gapAngle: 0
            value: Math.min(1, section.gaugeValue)
            colPrimary: section.gaugeColor
            colSecondary: Appearance.colors.colOutlineVariant
        }

        Column {
            anchors.centerIn: parent
            spacing: -2

            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Math.round(section.gaugeValue * 100) + "%"
                font.pixelSize: Appearance.font.pixelSize.huge
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer1
            }
            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: section.title
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
        }
    }

    // Detail rows
    Column {
        Layout.alignment: Qt.AlignHCenter
        spacing: 3

        Repeater {
            model: section.details

            Row {
                spacing: 4
                StyledText {
                    text: modelData.label
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                }
                StyledText {
                    text: modelData.value
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnLayer1
                }
            }
        }
    }

    // Usage history (CPU/MEM only); Loader so inactive popups (GPU) never
    // instantiate the chart, which drives ResourceHistory refreshes
    Loader {
        Layout.alignment: Qt.AlignHCenter
        active: section.showHistory
        visible: active

        sourceComponent: Column {
            spacing: 8

            Rectangle {
                width: section.contentWidth
                height: 1
                color: Appearance.colors.colOutlineVariant
            }

            IStatHistoryChart {
                accentColor: section.gaugeColor
                metricId: section.metricId
                chartWidth: section.contentWidth
            }
        }
    }

    // Process list
    Column {
        Layout.alignment: Qt.AlignHCenter
        width: section.processRowWidth
        Layout.minimumWidth: section.processRowWidth
        Layout.preferredWidth: section.processRowWidth
        visible: section.hasProcesses
        spacing: 4

        // Separator
        Rectangle {
            width: parent.width
            height: 1
            color: Appearance.colors.colOutlineVariant
        }

        Column {
            id: processColumn
            width: parent.width
            spacing: 2

            Repeater {
                model: section.processes

                Row {
                    spacing: section.processRowSpacing
                    width: processColumn.width

                    StyledText {
                        text: modelData.name
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnLayer1
                        width: section.processNameWidth
                        elide: Text.ElideRight
                    }
                    StyledText {
                        text: modelData[section.processValueKey]
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colSubtext
                        width: section.processValueWidth
                        horizontalAlignment: Text.AlignRight
                    }
                }
            }
        }
    }
}
