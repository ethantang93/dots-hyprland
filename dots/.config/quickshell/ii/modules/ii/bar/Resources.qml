import qs.modules.common
import qs.services
import QtQuick
import QtQuick.Layouts

MouseArea {
    id: root
    property bool borderless: Config.options.bar.borderless
    property bool alwaysShowAllResources: false
    implicitWidth: rowLayout.implicitWidth + rowLayout.anchors.leftMargin + rowLayout.anchors.rightMargin
    implicitHeight: Appearance.sizes.barHeight
    hoverEnabled: !Config.options.bar.tooltips.clickToShow

    RowLayout {
        id: rowLayout

        spacing: 0
        anchors.fill: parent
        anchors.leftMargin: 4
        anchors.rightMargin: 4

        Resource {
            iconName: "planner_review"
            percentage: ResourceUsage.cpuUsage
            shown: Config.options.bar.resources.alwaysShowCpu ||
                !(MprisController.activePlayer?.trackTitle?.length > 0) ||
                root.alwaysShowAllResources
            warningThreshold: Config.options.bar.resources.cpuWarningThreshold
        }

        ResourceTemp {
            iconName: "thermostat"
            temp: ResourceUsage.cpuTemp
            Layout.leftMargin: 6
            warningTemp: 80
        }

        Resource {
            iconName: "videocam"
            percentage: ResourceUsage.gpuUsage
            Layout.leftMargin: 6
            warningThreshold: 90
        }

        ResourceTemp {
            iconName: "thermostat"
            temp: ResourceUsage.gpuTemp
            Layout.leftMargin: 6
            warningTemp: 85
        }

        Resource {
            iconName: "memory"
            percentage: ResourceUsage.memoryUsedPercentage
            Layout.leftMargin: 6
            warningThreshold: Config.options.bar.resources.memoryWarningThreshold
        }
    }

    ResourcesPopup {
        hoverTarget: root
    }
}
