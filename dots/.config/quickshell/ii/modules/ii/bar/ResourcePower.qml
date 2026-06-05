import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

Item {
    id: root
    required property string iconName
    required property double watts
    property int warningWatts: 300
    property bool shown: true
    clip: true
    visible: width > 0 && height > 0
    implicitWidth: powerRowLayout.x < 0 ? 0 : powerRowLayout.implicitWidth
    implicitHeight: Appearance.sizes.barHeight
    property bool warning: watts >= warningWatts

    RowLayout {
        id: powerRowLayout
        spacing: 2
        x: shown ? 0 : -powerRowLayout.width
        anchors {
            verticalCenter: parent.verticalCenter
        }

        Item {
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: 20
            implicitHeight: 20

            MaterialSymbol {
                anchors.centerIn: parent
                font.weight: Font.DemiBold
                fill: 1
                text: iconName
                iconSize: Appearance.font.pixelSize.normal
                color: root.warning ? Appearance.colors.colError : Appearance.m3colors.m3onSecondaryContainer
            }
        }

        Item {
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: fullPowerTextMetrics.width
            implicitHeight: powerText.implicitHeight

            TextMetrics {
                id: fullPowerTextMetrics
                text: "999W"
                font.pixelSize: Appearance.font.pixelSize.small
            }

            StyledText {
                id: powerText
                anchors.centerIn: parent
                color: root.warning ? Appearance.colors.colError : Appearance.colors.colOnLayer1
                font.pixelSize: Appearance.font.pixelSize.small
                text: `${Math.round(watts)}W`
            }
        }

        Behavior on x {
            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
        }
    }

    Behavior on implicitWidth {
        NumberAnimation {
            duration: Appearance.animation.elementMove.duration
            easing.type: Appearance.animation.elementMove.type
            easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
        }
    }
}
