import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

MouseArea {
    id: gauge
    hoverEnabled: true
    required property string label
    required property real value
    required property color gaugeColor
    property real temp: -1
    property bool showTemp: temp >= 0

    // Popup properties
    property var details: []
    property var processes: []
    property string processValueKey: "usage"

    property int gaugeHeight: 22
    property int gaugeWidth: 8

    implicitWidth: gaugeRow.implicitWidth
    implicitHeight: gaugeRow.implicitHeight

    RowLayout {
        id: gaugeRow
        anchors.centerIn: parent
        spacing: 2

        // Vertical label (one letter per line)
        Column {
            Layout.alignment: Qt.AlignVCenter
            spacing: -1

            Repeater {
                model: gauge.label.split("")
                Text {
                    text: modelData
                    font.pixelSize: 7
                    font.weight: Font.Bold
                    font.family: Appearance.font.family.main
                    color: Appearance.colors.colOnLayer1
                    horizontalAlignment: Text.AlignHCenter
                    width: 9
                }
            }
        }

        // Vertical bar gauge
        Rectangle {
            Layout.alignment: Qt.AlignVCenter
            width: gauge.gaugeWidth
            height: gauge.gaugeHeight
            radius: gauge.gaugeWidth / 2
            color: Appearance.colors.colLayer2

            Rectangle {
                id: fill
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: parent.height * Math.max(0.05, Math.min(1, gauge.value))
                radius: parent.radius
                color: gauge.gaugeColor

                Behavior on height {
                    NumberAnimation {
                        duration: 800
                        easing.type: Easing.OutCubic
                    }
                }
            }
        }

        // Temperature to the right of the gauge
        Column {
            Layout.alignment: Qt.AlignVCenter
            Layout.topMargin: 5
            visible: gauge.showTemp
            spacing: -1

            Repeater {
                model: gauge.showTemp ? (Math.round(gauge.temp) + "°").split("") : []
                Text {
                    text: modelData
                    font.pixelSize: 7
                    font.family: Appearance.font.family.main
                    color: Appearance.colors.colSubtext
                    horizontalAlignment: Text.AlignHCenter
                    width: 8
                }
            }
        }
    }

    // Per-gauge popup
    StyledPopup {
        hoverTarget: gauge

        IStatPopupSection {
            anchors.centerIn: parent
            title: gauge.label
            gaugeColor: gauge.gaugeColor
            gaugeValue: gauge.value
            details: gauge.details
            processes: gauge.processes
            processValueKey: gauge.processValueKey
        }
    }
}
