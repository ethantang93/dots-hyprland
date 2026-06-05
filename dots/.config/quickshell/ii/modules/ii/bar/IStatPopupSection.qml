import qs.modules.common
import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: section
    required property string title
    required property color gaugeColor
    required property real gaugeValue
    property var details: []
    property var processes: []
    property string processValueKey: "usage"
    readonly property bool hasProcesses: section.processes && section.processes.length > 0
    readonly property int processNameWidth: 108
    readonly property int processValueWidth: 48
    readonly property int processRowSpacing: 6
    readonly property int processRowWidth: processNameWidth + processValueWidth + processRowSpacing

    spacing: 8

    // Title
    Text {
        Layout.alignment: Qt.AlignHCenter
        text: section.title
        font.pixelSize: Appearance.font.pixelSize.small
        font.weight: Font.Bold
        font.family: Appearance.font.family.main
        color: Appearance.colors.colOnLayer1
    }

    // Tall gauge bar
    Rectangle {
        Layout.alignment: Qt.AlignHCenter
        width: 14
        height: 80
        radius: 7
        color: Appearance.colors.colLayer2

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: parent.height * Math.max(0.03, Math.min(1, section.gaugeValue))
            radius: parent.radius
            color: section.gaugeColor

            Behavior on height {
                NumberAnimation {
                    duration: 800
                    easing.type: Easing.OutCubic
                }
            }
        }
    }

    // Percentage below gauge
    Text {
        Layout.alignment: Qt.AlignHCenter
        text: Math.round(section.gaugeValue * 100) + "%"
        font.pixelSize: Appearance.font.pixelSize.normal
        font.weight: Font.DemiBold
        font.family: Appearance.font.family.main
        color: section.gaugeColor
    }

    // Detail rows
    Column {
        Layout.alignment: Qt.AlignHCenter
        spacing: 3

        Repeater {
            model: section.details

            Row {
                spacing: 4
                Text {
                    text: modelData.label
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.family: Appearance.font.family.main
                    color: Appearance.colors.colSubtext
                }
                Text {
                    text: modelData.value
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.family: Appearance.font.family.main
                    color: Appearance.colors.colOnLayer1
                }
            }
        }
    }

    // Process list
    Column {
        Layout.alignment: Qt.AlignLeft
        width: section.processRowWidth
        Layout.minimumWidth: section.processRowWidth
        Layout.preferredWidth: section.processRowWidth
        visible: section.hasProcesses
        spacing: 4

        // Separator
        Rectangle {
            width: parent.width
            height: 1
            color: Appearance.colors.colOutlineVariant
        }

        Column {
            id: processColumn
            width: parent.width
            spacing: 2

            Repeater {
                model: section.processes

                Row {
                    spacing: section.processRowSpacing
                    width: processColumn.width

                    Text {
                        text: modelData.name
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.family: Appearance.font.family.main
                        color: Appearance.colors.colOnLayer1
                        width: section.processNameWidth
                        elide: Text.ElideRight
                    }
                    Text {
                        text: section.processValueKey === "mem" ? modelData.mem : modelData.usage
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.family: Appearance.font.family.main
                        color: Appearance.colors.colSubtext
                        width: section.processValueWidth
                        horizontalAlignment: Text.AlignRight
                    }
                }
            }
        }
    }
}
