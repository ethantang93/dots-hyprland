import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: root
    radius: Appearance.rounding.normal
    color: Appearance.colors.colLayer1
    implicitHeight: contentColumn.implicitHeight + 16
    Layout.fillWidth: true

    ColumnLayout {
        id: contentColumn
        anchors.fill: parent
        anchors.margins: 12
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            MaterialSymbol {
                text: "mode_fan"
                iconSize: 22
                color: Appearance.colors.colOnLayer1
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                StyledText {
                    text: Translation.tr("GPU Fan")
                    color: Appearance.colors.colOnLayer1
                    font.pixelSize: Appearance.font.pixelSize.normal
                }
                StyledText {
                    text: GpuFanControl.manual
                        ? Translation.tr("Manual · %1%").arg(GpuFanControl.currentSpeed)
                        : Translation.tr("Auto · %1%").arg(GpuFanControl.currentSpeed)
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                }
            }
            StyledSwitch {
                checked: GpuFanControl.manual
                onToggled: GpuFanControl.setManual(checked)
            }
        }

        StyledSlider {
            id: speedSlider
            Layout.fillWidth: true
            configuration: StyledSlider.Configuration.M
            from: GpuFanControl.minSpeed
            to: GpuFanControl.maxSpeed
            stepSize: 1
            enabled: GpuFanControl.manual
            opacity: enabled ? 1 : 0.5
            usePercentTooltip: false
            tooltipContent: `${Math.round(value)}%`
            value: GpuFanControl.targetSpeed

            onMoved: GpuFanControl.setSpeed(value)

            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }

            MaterialSymbol {
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                anchors.rightMargin: 10
                iconSize: 20
                text: "mode_fan"
                color: speedSlider.value >= (speedSlider.to - speedSlider.from) * 0.9 + speedSlider.from
                    ? Appearance.colors.colOnPrimary
                    : Appearance.colors.colOnSecondaryContainer
            }
        }
    }
}
