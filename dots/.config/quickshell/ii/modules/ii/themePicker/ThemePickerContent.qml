import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.widgets

Rectangle {
    id: root
    radius: 28
    color: Appearance.m3colors.m3surfaceContainerLow
    border.color: Appearance.m3colors.m3outlineVariant
    border.width: 1
    property var themes: []
    property string activeTheme: ""
    property int selectedIndex: 0
    property string query: ""
    property string filterMode: "All"
    property string status: ""
    property bool failed: false
    property bool useWallpaper: false
    readonly property var filtered: themes.filter(t =>
        t.name.toLowerCase().includes(query.toLowerCase()) &&
        (filterMode === "All" || (filterMode === "Dark" ? t.dark : !t.dark)))
    readonly property var selected: filtered[Math.min(selectedIndex, filtered.length - 1)] ?? null
    readonly property bool busy: applyProcess.running
    readonly property string backend: Directories.scriptPath + "/colors/named-theme.py"
    readonly property color muted: Appearance.m3colors.m3onSurfaceVariant
    signal closeRequested()
    signal operationFinished()

    Component.onCompleted: catalogProcess.running = true
    onFilteredChanged: selectedIndex = 0

    function moveSelection(delta) {
        selectedIndex = Math.max(0, Math.min(filtered.length - 1, selectedIndex + delta));
        grid.positionViewAtIndex(selectedIndex, GridView.Contain);
    }
    function searchFor(text) { search.text = text; search.forceActiveFocus(); }
    function applyTheme(wallpaperColors) {
        if (busy || (!wallpaperColors && !selected)) return;
        status = wallpaperColors ? "Restoring wallpaper colors…" : "Applying " + selected.name + "…";
        failed = false;
        applyProcess.command = wallpaperColors
            ? ["python3", backend, "wallpaper"]
            : ["python3", backend, "apply", selected.id].concat(useWallpaper ? ["--wallpaper"] : []);
        applyProcess.running = true;
    }

    Process {
        id: catalogProcess
        command: ["python3", root.backend, "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text);
                    root.themes = data.themes;
                    root.activeTheme = data.active;
                    const index = root.filtered.findIndex(t => t.id === data.active);
                    root.selectedIndex = Math.max(0, index);
                } catch (e) { root.status = "Could not load themes."; root.failed = true; }
            }
        }
    }
    Process {
        id: applyProcess
        property string errors: ""
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.activeTheme = JSON.parse(text).active; } catch (e) {}
            }
        }
        stderr: StdioCollector { onStreamFinished: applyProcess.errors = text }
        onExited: (code, exitStatus) => {
            root.failed = code !== 0;
            root.status = code === 0
                ? (root.activeTheme ? "Theme applied. Make yourself at home." : "Wallpaper colors restored.")
                : "Could not apply theme: " + errors.slice(-240);
            root.operationFinished();
        }
    }

    component Pill: Button {
        id: pill
        property bool selected: false
        property bool accent: false
        hoverEnabled: true
        implicitHeight: 38
        implicitWidth: label.implicitWidth + 30
        background: Rectangle {
            radius: height / 2
            color: pill.accent ? Appearance.m3colors.m3primary
                : pill.selected ? Appearance.m3colors.m3secondaryContainer
                : pill.hovered ? Appearance.m3colors.m3surfaceContainerHighest : Appearance.m3colors.m3surfaceContainer
            Behavior on color { ColorAnimation { duration: 160 } }
        }
        contentItem: StyledText {
            id: label
            text: pill.text
            horizontalAlignment: Text.AlignHCenter
            color: pill.accent ? Appearance.m3colors.m3onPrimary : Appearance.m3colors.m3onSurface
            font.pixelSize: 13
            font.weight: Font.Medium
        }
        opacity: enabled ? 1 : .45
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 28
        spacing: 20
        RowLayout {
            Layout.fillWidth: true
            ColumnLayout {
                spacing: 3
                StyledText { text: "MAKE IT YOURS"; font.pixelSize: 10; font.letterSpacing: 2.4; color: root.muted }
                StyledText { text: "Themes"; font.pixelSize: 32; font.weight: Font.DemiBold }
            }
            Item { Layout.fillWidth: true }
            Pill {
                text: root.activeTheme ? "Wallpaper colors" : "✓  Wallpaper colors"
                selected: !root.activeTheme
                enabled: !root.busy
                onClicked: root.applyTheme(true)
                ToolTip.visible: hovered
                ToolTip.text: "Return to colors generated from your wallpaper"
            }
            Pill { text: "✕"; implicitWidth: 38; onClicked: root.closeRequested() }
        }

        RowLayout {
            spacing: 20
            Layout.fillWidth: true
            Layout.fillHeight: true
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 14
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 7
                    TextField {
                        id: search
                        Layout.fillWidth: true
                        implicitHeight: 40
                        placeholderText: "Search themes…"
                        placeholderTextColor: root.muted
                        color: Appearance.m3colors.m3onSurface
                        selectionColor: Appearance.m3colors.m3primaryContainer
                        font.family: Appearance.font.family.main
                        font.pixelSize: 14
                        leftPadding: 15
                        focus: true
                        selectByMouse: true
                        background: Rectangle { radius: 20; color: Appearance.m3colors.m3surfaceContainerHigh }
                        onTextChanged: root.query = text
                        Keys.onPressed: event => {
                            if (event.key === Qt.Key_Down) { root.moveSelection(2); event.accepted = true; }
                            else if (event.key === Qt.Key_Up) { root.moveSelection(-2); event.accepted = true; }
                            else if (event.key === Qt.Key_Right && text.length === 0) { root.moveSelection(1); event.accepted = true; }
                            else if (event.key === Qt.Key_Left && text.length === 0) { root.moveSelection(-1); event.accepted = true; }
                            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { root.applyTheme(false); event.accepted = true; }
                            else if (event.key === Qt.Key_Escape) { root.closeRequested(); event.accepted = true; }
                        }
                    }
                    Repeater {
                        model: ["All", "Dark", "Light"]
                        Pill {
                            required property string modelData
                            text: modelData
                            selected: root.filterMode === modelData
                            implicitWidth: 54
                            onClicked: { root.filterMode = modelData; search.forceActiveFocus(); }
                        }
                    }
                }
                GridView {
                    id: grid
                    Layout.fillHeight: true
                    Layout.fillWidth: true
                    clip: true
                    cellWidth: width / 2
                    cellHeight: 171
                    model: root.filtered
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                    delegate: Item {
                        id: card
                        required property var modelData
                        required property int index
                        width: grid.cellWidth
                        height: grid.cellHeight
                        Rectangle {
                            anchors.fill: parent
                            anchors.rightMargin: 10
                            anchors.bottomMargin: 10
                            radius: 17
                            color: card.modelData.background
                            border.width: root.selectedIndex === card.index ? 2 : 1
                            border.color: root.selectedIndex === card.index ? card.modelData.accent : Qt.alpha(card.modelData.foreground, .14)
                            scale: mouse.containsMouse ? .985 : 1
                            Behavior on scale { NumberAnimation { duration: 140 } }
                            Item {
                                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 5 }
                                height: 91
                                layer.enabled: true
                                layer.effect: OpacityMask { maskSource: Rectangle { width: 300; height: 91; radius: 12 } }
                                Image { anchors.fill: parent; source: card.modelData.wallpaper; fillMode: Image.PreserveAspectCrop; asynchronous: true; sourceSize.width: 520 }
                                Rectangle { anchors.fill: parent; color: Qt.alpha(card.modelData.background, .13) }
                                Rectangle {
                                    anchors { right: parent.right; top: parent.top; margins: 7 }
                                    visible: root.activeTheme === card.modelData.id
                                    width: 60; height: 23; radius: 12
                                    color: card.modelData.accent
                                    Text { anchors.centerIn: parent; text: "ACTIVE"; font.pixelSize: 9; font.bold: true; color: card.modelData.background }
                                }
                            }
                            Column {
                                anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 14 }
                                spacing: 7
                                Text { text: card.modelData.name; color: card.modelData.foreground; font.family: Appearance.font.family.main; font.pixelSize: 14; font.weight: Font.Medium }
                                Row {
                                    spacing: 5
                                    Repeater { model: card.modelData.swatches; Rectangle { required property string modelData; width: 18; height: 7; radius: 3; color: modelData } }
                                }
                            }
                            MouseArea {
                                id: mouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: { root.selectedIndex = card.index; search.forceActiveFocus(); }
                                onDoubleClicked: root.applyTheme(false)
                            }
                        }
                    }
                    StyledText { anchors.centerIn: parent; visible: root.filtered.length === 0; text: "No matching themes"; color: root.muted }
                }
                StyledText { text: root.filtered.length + " themes  ·  ↑ ↓ ← → browse  ·  Enter apply  ·  Esc close"; font.pixelSize: 11; color: root.muted }
            }

            Rectangle {
                id: preview
                Layout.preferredWidth: root.width > 950 ? 364 : 310
                Layout.fillHeight: true
                radius: 21
                color: root.selected?.background ?? Appearance.m3colors.m3surfaceContainer
                border.color: Qt.alpha(root.selected?.foreground ?? "#ffffff", .12)
                Behavior on color { ColorAnimation { duration: 200 } }
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 20
                    spacing: 15
                    StyledText { text: "PREVIEW"; font.pixelSize: 10; font.letterSpacing: 2; color: Qt.alpha(root.selected?.foreground ?? "#ffffff", .65) }
                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 164
                        layer.enabled: true
                        layer.effect: OpacityMask { maskSource: Rectangle { width: 364; height: 164; radius: 13 } }
                        Image { anchors.fill: parent; source: root.selected?.wallpaper ?? ""; fillMode: Image.PreserveAspectCrop; asynchronous: true; sourceSize.width: 800 }
                        Rectangle {
                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 9 }
                            height: 21; radius: 8
                            color: Qt.alpha(root.selected?.background ?? "#000000", .9)
                            Row { anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: 9 } spacing: 4; Repeater { model: 3; Rectangle { required property int index; width: index === 0 ? 14 : 5; height: 5; radius: 3; color: root.selected?.accent ?? "#ffffff"; opacity: index === 0 ? 1 : .35 } } }
                            Text { anchors.centerIn: parent; text: "Friday, 11:24"; color: root.selected?.foreground ?? "#fff"; font.pixelSize: 8 }
                        }
                    }
                    ColumnLayout {
                        spacing: 4
                        StyledText { text: root.selected?.name ?? "Choose a theme"; font.pixelSize: 25; font.weight: Font.DemiBold; color: root.selected?.foreground ?? "#fff" }
                        StyledText { text: root.selected ? (root.selected.dark ? "Dark palette" : "Light palette") + "  ·  Omarchy collection" : ""; color: Qt.alpha(root.selected?.foreground ?? "#fff", .6); font.pixelSize: 12 }
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 105
                        radius: 12
                        color: Qt.alpha(root.selected?.foreground ?? "#ffffff", .055)
                        Column {
                            anchors { fill: parent; margins: 14 }
                            spacing: 7
                            Text { text: "~/projects  main"; font.family: Appearance.font.family.monospace; font.pixelSize: 11; color: Qt.alpha(root.selected?.foreground ?? "#fff", .6) }
                            Text { text: "❯  echo 'Hello, world'"; font.family: Appearance.font.family.monospace; font.pixelSize: 12; color: root.selected?.accent ?? "#fff" }
                            Row { spacing: 0; Repeater { model: root.selected?.swatches ?? []; Rectangle { required property string modelData; width: 30; height: 15; color: modelData } } }
                        }
                    }
                    Item { Layout.fillHeight: true }
                    CheckBox {
                        id: wallpaperCheck
                        text: "Use matching wallpaper"
                        checked: root.useWallpaper
                        onToggled: root.useWallpaper = checked
                        enabled: !root.busy && !!root.selected?.wallpaper
                        contentItem: StyledText { text: wallpaperCheck.text; leftPadding: wallpaperCheck.indicator.width + 8; font.pixelSize: 12; color: root.selected?.foreground ?? "#fff" }
                        indicator: Rectangle {
                            implicitWidth: 18; implicitHeight: 18; y: (wallpaperCheck.height - height) / 2; radius: 5
                            color: wallpaperCheck.checked ? (root.selected?.accent ?? "#fff") : "transparent"
                            border.width: 1; border.color: root.selected?.accent ?? "#fff"
                            Text { anchors.centerIn: parent; text: "✓"; visible: wallpaperCheck.checked; color: root.selected?.background ?? "#000" }
                        }
                    }
                    Pill {
                        text: root.busy ? "Applying…" : root.activeTheme === root.selected?.id ? "Apply again" : "Apply theme"
                        Layout.fillWidth: true
                        implicitHeight: 44
                        accent: true
                        enabled: !root.busy && !!root.selected
                        onClicked: root.applyTheme(false)
                    }
                }
            }
        }
        StyledText {
            Layout.fillWidth: true
            text: root.status || "Colors for your desktop, terminals and apps. Your wallpaper stays yours."
            color: root.failed ? Appearance.m3colors.m3error : root.muted
            font.pixelSize: 12
            wrapMode: Text.Wrap
        }
    }
    Shortcut { sequence: "Escape"; onActivated: root.closeRequested() }
}
