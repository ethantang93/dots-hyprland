import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

MouseArea {
    id: gauge
    required property string label
    required property real value
    required property color gaugeColor
    property real temp: -1
    property bool showTemp: temp >= 0

    // Popup properties
    property var details: []
    property var processes: []
    property string processValueKey: "usage"
    property string metricId: ""
    property bool showHistory: false

    // Click-toggled popup, coordinated by the parent widget
    property bool expanded: false
    signal toggleRequested()
    signal dismissRequested()

    onClicked: gauge.toggleRequested()

    property int gaugeHeight: 22
    property int gaugeWidth: 8

    implicitWidth: gaugeRow.implicitWidth
    implicitHeight: gaugeRow.implicitHeight

    RowLayout {
        id: gaugeRow
        anchors.centerIn: parent
        spacing: 2

        // Vertical label (one letter per line)
        StyledText {
            Layout.alignment: Qt.AlignVCenter
            text: gauge.label.split("").join("\n")
            font.pixelSize: 7
            font.weight: Font.Bold
            lineHeight: 0.85
            color: Appearance.colors.colOnLayer1
            horizontalAlignment: Text.AlignHCenter
            width: 9
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
        StyledText {
            Layout.alignment: Qt.AlignVCenter
            Layout.topMargin: 5
            visible: gauge.showTemp
            text: gauge.showTemp ? (Math.round(gauge.temp) + "°").split("").join("\n") : ""
            font.pixelSize: 7
            lineHeight: 0.85
            color: Appearance.colors.colSubtext
            horizontalAlignment: Text.AlignHCenter
            width: 8
        }
    }

    // Per-gauge popup, opened on click
    StyledPopup {
        hoverTarget: gauge
        active: gauge.expanded
        dismissOnOutsideClick: true
        onDismissed: gauge.dismissRequested()

        IStatPopupSection {
            anchors.centerIn: parent
            title: gauge.label
            gaugeColor: gauge.gaugeColor
            gaugeValue: gauge.value
            details: gauge.details
            processes: gauge.processes
            processValueKey: gauge.processValueKey
            metricId: gauge.metricId
            showHistory: gauge.showHistory
        }
    }
}
