import qs.modules.common
import qs.services
import QtQuick

/*
 * Usage bar with a marker at how much of the window has elapsed.
 * Fill left of the marker = under pace, past it = burning faster than the window allows.
 */
Item {
    id: root
    property real used: 0 // 0..100
    property real elapsed: 0 // 0..1
    property real barHeight: 4
    property color fillColor: AiUsage.usageColor(used, elapsed)

    implicitWidth: 40
    implicitHeight: barHeight + 4

    Rectangle {
        id: track
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: root.barHeight
        radius: height / 2
        color: Appearance.m3colors.m3secondaryContainer

        Rectangle {
            anchors {
                left: parent.left
                top: parent.top
                bottom: parent.bottom
            }
            width: parent.width * Math.max(0, Math.min(1, root.used / 100))
            radius: parent.radius
            color: root.fillColor
            Behavior on width {
                animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
            }
            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }
    }

    // Pace marker
    Rectangle {
        visible: root.elapsed > 0
        anchors.verticalCenter: parent.verticalCenter
        x: Math.round(track.width * root.elapsed - width / 2)
        width: 2
        height: root.height
        radius: 1
        color: Appearance.colors.colOnLayer1
    }
}
