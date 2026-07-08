import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

Item {
    id: root
    implicitWidth: rowLayout.implicitWidth + 12
    implicitHeight: Appearance.sizes.barHeight

    // Which gauge's popup is open ("" = none); ensures only one at a time
    property string expandedMetric: ""

    function toggleMetric(metricId) {
        expandedMetric = (expandedMetric === metricId) ? "" : metricId;
    }

    // Single definition per metric; the gauges below are stamped from this
    readonly property var metrics: [
        { id: "cpu", label: "CPU", color: "#D946A8", showHistory: true, processKey: "usage" },
        { id: "gpu", label: "GPU", color: "#A855F7", showHistory: false, processKey: "usage" },
        { id: "mem", label: "MEM", color: "#3B82F6", showHistory: true, processKey: "mem" },
    ]

    // Property accesses inside these are tracked by QML, so bindings that
    // call them re-evaluate when ResourceUsage updates
    function metricValue(id) {
        if (id === "cpu") return ResourceUsage.cpuUsage;
        if (id === "gpu") return ResourceUsage.gpuUsage;
        return ResourceUsage.memoryUsedPercentage;
    }
    function metricTemp(id) {
        if (id === "cpu") return ResourceUsage.cpuTemp;
        if (id === "gpu") return ResourceUsage.gpuTemp;
        return -1;
    }
    function metricDetails(id) {
        if (id === "cpu") return [
            { label: "Load", value: Math.round(ResourceUsage.cpuUsage * 100) + "%" },
            { label: "Temp", value: Math.round(ResourceUsage.cpuTemp) + "°C" },
        ];
        if (id === "gpu") return [
            { label: "Load", value: Math.round(ResourceUsage.gpuUsage * 100) + "%" },
            { label: "Temp", value: Math.round(ResourceUsage.gpuTemp) + "°C" },
        ];
        return [
            { label: "Used", value: ResourceUsage.kbToGbString(ResourceUsage.memoryUsed) },
            { label: "Free", value: ResourceUsage.kbToGbString(ResourceUsage.memoryFree) },
            { label: "Total", value: ResourceUsage.kbToGbString(ResourceUsage.memoryTotal) },
        ];
    }
    function metricProcesses(id) {
        if (id === "cpu") return ResourceUsage.topCpuProcesses;
        if (id === "mem") return ResourceUsage.topMemProcesses;
        return [];
    }

    RowLayout {
        id: rowLayout
        anchors.centerIn: parent
        spacing: 8

        Repeater {
            model: root.metrics

            IStatGauge {
                required property var modelData
                label: modelData.label
                metricId: modelData.id
                gaugeColor: modelData.color
                value: root.metricValue(modelData.id)
                temp: root.metricTemp(modelData.id)
                details: root.metricDetails(modelData.id)
                processes: root.metricProcesses(modelData.id)
                processValueKey: modelData.processKey
                showHistory: modelData.showHistory
                expanded: root.expandedMetric === modelData.id
                onToggleRequested: root.toggleMetric(modelData.id)
                // Only clear if we still own the popup: a click on another gauge
                // may have switched expandedMetric before this dismissal lands
                onDismissRequested: if (root.expandedMetric === modelData.id) root.expandedMetric = ""
            }
        }

        MouseArea {
            id: powerDisplay
            hoverEnabled: true
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: powerRow.implicitWidth
            implicitHeight: powerRow.implicitHeight

            RowLayout {
                id: powerRow
                anchors.centerIn: parent
                spacing: 2

                Column {
                    Layout.alignment: Qt.AlignVCenter
                    spacing: -1

                    MaterialSymbol {
                        text: "bolt"
                        iconSize: 10
                        fill: 1
                        color: "#FACC15"
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                }

                Column {
                    Layout.alignment: Qt.AlignVCenter
                    spacing: -1

                    Repeater {
                        model: (Math.round(ResourceUsage.totalPower) + "W").split("")
                        Text {
                            text: modelData
                            font.pixelSize: 7
                            font.family: Appearance.font.family.main
                            font.weight: Font.Bold
                            color: Appearance.colors.colOnLayer1
                            horizontalAlignment: Text.AlignHCenter
                            width: 9
                        }
                    }
                }
            }

            StyledPopup {
                hoverTarget: powerDisplay

                Column {
                    anchors.centerIn: parent
                    spacing: 4
                    padding: 8

                    StyledText {
                        text: "System Power"
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.Bold
                        color: Appearance.colors.colOnLayer1
                    }
                    StyledText {
                        text: "CPU: " + Math.round(ResourceUsage.cpuPower) + " W"
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colSubtext
                    }
                    StyledText {
                        text: "GPU: " + Math.round(ResourceUsage.gpuPower) + " W"
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colSubtext
                    }
                    StyledText {
                        text: "Total: " + Math.round(ResourceUsage.totalPower) + " W"
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer1
                    }
                }
            }
        }
    }
}
