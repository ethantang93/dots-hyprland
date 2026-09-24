pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.widgets
import qs.services
import Quickshell
import QtQuick
import QtQuick.Layouts

MouseArea {
    id: root
    implicitWidth: rowLayout.implicitWidth + 10 * 2
    implicitHeight: Appearance.sizes.barHeight

    acceptedButtons: Qt.LeftButton | Qt.RightButton
    hoverEnabled: !Config.options.bar.tooltips.clickToShow

    onPressed: mouse => {
        if (mouse.button === Qt.RightButton) {
            AiUsage.refresh(true);
            mouse.accepted = false;
        }
    }

    RowLayout {
        id: rowLayout
        anchors.centerIn: parent
        spacing: 10

        Repeater {
            model: AiUsage.accounts

            // One account: ring with its session (5h) usage, then the percentage
            Row {
                id: accountItem
                required property var modelData
                readonly property var session: (modelData.windows ?? []).find(w => w.key === "5h")
                readonly property real used: session ? AiUsage.effectiveUsed(session) : 0
                spacing: 4
                opacity: modelData.status === "ok" ? 1 : 0.55

                AiUsageRing {
                    anchors.verticalCenter: parent.verticalCenter
                    label: accountItem.modelData.short
                    used: accountItem.used
                    elapsed: accountItem.session ? AiUsage.elapsedFraction(accountItem.session) : 0
                }

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: accountItem.session ? `${Math.round(accountItem.used)}%` : "--"
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnLayer1
                }
            }
        }
    }

    AiUsagePopup {
        hoverTarget: root
    }
}
