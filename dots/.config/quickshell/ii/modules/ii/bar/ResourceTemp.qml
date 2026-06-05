import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

Item {
    id: root
    required property string iconName
    required property double temp
    property int warningTemp: 80
    property bool shown: true
    clip: true
    visible: width > 0 && height > 0
    implicitWidth: tempRowLayout.x < 0 ? 0 : tempRowLayout.implicitWidth
    implicitHeight: Appearance.sizes.barHeight
    property bool warning: temp >= warningTemp

    RowLayout {
        id: tempRowLayout
        spacing: 2
        x: shown ? 0 : -tempRowLayout.width
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
            implicitWidth: fullTempTextMetrics.width
            implicitHeight: tempText.implicitHeight

            TextMetrics {
                id: fullTempTextMetrics
                text: "100°"
                font.pixelSize: Appearance.font.pixelSize.small
            }

            StyledText {
                id: tempText
                anchors.centerIn: parent
                color: root.warning ? Appearance.colors.colError : Appearance.colors.colOnLayer1
                font.pixelSize: Appearance.font.pixelSize.small
                text: `${Math.round(temp)}°`
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
