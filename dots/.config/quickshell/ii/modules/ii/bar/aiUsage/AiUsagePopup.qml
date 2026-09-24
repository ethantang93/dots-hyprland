pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
import qs.modules.ii.bar

StyledPopup {
    id: root

    ColumnLayout {
        anchors.centerIn: parent
        spacing: 10

        StyledPopupHeaderRow {
            icon: "data_usage"
            label: Translation.tr("AI usage")
        }

        Repeater {
            model: AiUsage.accounts

            ColumnLayout {
                id: account
                required property var modelData
                spacing: 6

                RowLayout {
                    spacing: 6
                    StyledText {
                        text: account.modelData.label
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnSurfaceVariant
                    }
                    StyledText {
                        visible: !!account.modelData.plan
                        text: (account.modelData.plan ?? "").charAt(0).toUpperCase() + (account.modelData.plan ?? "").slice(1)
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                }

                StyledText {
                    visible: account.modelData.status !== "ok"
                    Layout.maximumWidth: 260
                    wrapMode: Text.Wrap
                    text: (account.modelData.status === "stale" ? Translation.tr("Stale: ") : Translation.tr("Error: ")) + (account.modelData.error ?? "")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.m3colors.m3error
                }

                Repeater {
                    model: account.modelData.windows ?? []

                    ColumnLayout {
                        id: windowItem
                        required property var modelData
                        readonly property real used: AiUsage.effectiveUsed(modelData)
                        readonly property real delta: AiUsage.paceDelta(modelData)
                        spacing: 3

                        RowLayout {
                            spacing: 4
                            StyledText {
                                text: windowItem.modelData.label
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colOnSurfaceVariant
                            }
                            StyledText {
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignRight
                                text: `${Math.round(windowItem.used)}%`
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colOnSurfaceVariant
                            }
                        }

                        AiUsagePaceBar {
                            Layout.fillWidth: true
                            implicitWidth: 260
                            barHeight: 6
                            used: windowItem.used
                            elapsed: AiUsage.elapsedFraction(windowItem.modelData)
                        }

                        RowLayout {
                            spacing: 4
                            StyledText {
                                text: {
                                    const d = Math.round(windowItem.delta);
                                    if (Math.abs(d) < 1) return Translation.tr("On pace");
                                    return d > 0 ? Translation.tr("%1 pts ahead of pace").arg(d) : Translation.tr("%1 pts under pace").arg(-d);
                                }
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: windowItem.delta > 15 ? Appearance.m3colors.m3error : Appearance.colors.colSubtext
                            }
                            StyledText {
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignRight
                                visible: !!windowItem.modelData.resetsAt
                                text: Translation.tr("Resets in %1").arg(AiUsage.resetsIn(windowItem.modelData))
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colSubtext
                            }
                        }
                    }
                }
            }
        }

        StyledText {
            Layout.alignment: Qt.AlignHCenter
            text: AiUsage.accounts.length === 0 ? Translation.tr("No accounts found") : Translation.tr("Right-click to refresh")
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }
    }
}
