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

    function formatKB(kb) {
        return (kb / (1024 * 1024)).toFixed(1) + " GB";
    }

    RowLayout {
        id: rowLayout
        anchors.centerIn: parent
        spacing: 8

        IStatGauge {
            label: "CPU"
            value: ResourceUsage.cpuUsage
            gaugeColor: "#D946A8"
            temp: ResourceUsage.cpuTemp
            details: [
                { label: "Load", value: Math.round(ResourceUsage.cpuUsage * 100) + "%" },
                { label: "Temp", value: Math.round(ResourceUsage.cpuTemp) + "°C" },
            ]
            processes: ResourceUsage.topCpuProcesses
            processValueKey: "usage"
            metricId: "cpu"
            showHistory: true
            expanded: root.expandedMetric === "cpu"
            onToggleRequested: root.toggleMetric("cpu")
            // Only clear if we still own the popup: a click on another gauge may
            // have already switched expandedMetric before this dismissal lands
            onDismissRequested: if (root.expandedMetric === "cpu") root.expandedMetric = ""
        }

        IStatGauge {
            label: "GPU"
            value: ResourceUsage.gpuUsage
            gaugeColor: "#A855F7"
            temp: ResourceUsage.gpuTemp
            details: [
                { label: "Load", value: Math.round(ResourceUsage.gpuUsage * 100) + "%" },
                { label: "Temp", value: Math.round(ResourceUsage.gpuTemp) + "°C" },
            ]
            metricId: "gpu"
            expanded: root.expandedMetric === "gpu"
            onToggleRequested: root.toggleMetric("gpu")
            // Only clear if we still own the popup: a click on another gauge may
            // have already switched expandedMetric before this dismissal lands
            onDismissRequested: if (root.expandedMetric === "gpu") root.expandedMetric = ""
        }

        IStatGauge {
            label: "MEM"
            value: ResourceUsage.memoryUsedPercentage
            gaugeColor: "#3B82F6"
            details: [
                { label: "Used", value: root.formatKB(ResourceUsage.memoryUsed) },
                { label: "Free", value: root.formatKB(ResourceUsage.memoryFree) },
                { label: "Total", value: root.formatKB(ResourceUsage.memoryTotal) },
            ]
            processes: ResourceUsage.topMemProcesses
            processValueKey: "mem"
            metricId: "mem"
            showHistory: true
            expanded: root.expandedMetric === "mem"
            onToggleRequested: root.toggleMetric("mem")
            // Only clear if we still own the popup: a click on another gauge may
            // have already switched expandedMetric before this dismissal lands
            onDismissRequested: if (root.expandedMetric === "mem") root.expandedMetric = ""
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
