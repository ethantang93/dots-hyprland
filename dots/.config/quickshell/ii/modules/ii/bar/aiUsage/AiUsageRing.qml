import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import QtQuick

/*
 * Circular usage meter with a tick at how much of the window has elapsed.
 */
Item {
    id: root
    property real used: 0 // 0..100
    property real elapsed: 0 // 0..1
    property string label: ""
    property int size: 28
    property int lineWidth: 3

    implicitWidth: size
    implicitHeight: size

    CircularProgress {
        id: ring
        anchors.fill: parent
        implicitSize: root.size
        lineWidth: root.lineWidth
        value: Math.max(0, Math.min(1, root.used / 100))
        colPrimary: AiUsage.usageColor(root.used, root.elapsed)
        colSecondary: ColorUtils.transparentize(Appearance.colors.colOnLayer1, 0.75)
    }

    // Pace tick, rotated around the center to the elapsed angle
    Item {
        visible: root.elapsed > 0
        anchors.fill: parent
        rotation: root.elapsed * 360
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 0
            width: 2
            height: root.lineWidth + 2
            radius: 1
            color: Appearance.colors.colOnLayer1
        }
    }

    StyledText {
        anchors.centerIn: parent
        text: root.label
        font.pixelSize: Appearance.font.pixelSize.smallest
        font.weight: Font.DemiBold
        color: Appearance.colors.colOnLayer1
    }
}
