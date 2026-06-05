import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

StyledPopup {
    id: root

    function formatKB(kb) {
        return (kb / (1024 * 1024)).toFixed(1) + " GB";
    }

    Row {
        anchors.centerIn: parent
        spacing: 16

        // CPU section
        IStatPopupSection {
            title: "CPU"
            gaugeColor: "#D946A8"
            gaugeValue: ResourceUsage.cpuUsage
            details: [
                { label: "Load", value: Math.round(ResourceUsage.cpuUsage * 100) + "%" },
                { label: "Temp", value: Math.round(ResourceUsage.cpuTemp) + "°C" },
            ]
            processes: ResourceUsage.topCpuProcesses
            processValueKey: "usage"
        }

        // GPU section
        IStatPopupSection {
            title: "GPU"
            gaugeColor: "#A855F7"
            gaugeValue: ResourceUsage.gpuUsage
            details: [
                { label: "Load", value: Math.round(ResourceUsage.gpuUsage * 100) + "%" },
                { label: "Temp", value: Math.round(ResourceUsage.gpuTemp) + "°C" },
            ]
        }

        // RAM section
        IStatPopupSection {
            title: "RAM"
            gaugeColor: "#3B82F6"
            gaugeValue: ResourceUsage.memoryUsedPercentage
            details: [
                { label: "Used", value: root.formatKB(ResourceUsage.memoryUsed) },
                { label: "Free", value: root.formatKB(ResourceUsage.memoryFree) },
                { label: "Total", value: root.formatKB(ResourceUsage.memoryTotal) },
            ]
            processes: ResourceUsage.topMemProcesses
            processValueKey: "mem"
        }

        // Swap section
        IStatPopupSection {
            visible: ResourceUsage.swapTotal > 0
            title: "Swap"
            gaugeColor: "#F59E0B"
            gaugeValue: ResourceUsage.swapUsedPercentage
            details: [
                { label: "Used", value: root.formatKB(ResourceUsage.swapUsed) },
                { label: "Free", value: root.formatKB(ResourceUsage.swapFree) },
                { label: "Total", value: root.formatKB(ResourceUsage.swapTotal) },
            ]
        }
    }
}
