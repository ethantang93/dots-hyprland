//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "modules/common"
import "services"
import "modules/ii/themePicker"

ShellRoot {
    Component.onCompleted: MaterialThemeLoader.reapplyTheme()
    IpcHandler {
        target: "themePicker"
        function close(): void { picker.closeRequested() }
        function toggle(): void {
            if (!window.visible) window.visible = true;
            else picker.closeRequested();
        }
        function search(query: string): void { picker.searchFor(query) }
        function state(): string {
            return JSON.stringify({query: picker.query, count: picker.filtered.length,
                selected: picker.selected?.id ?? "", active: picker.activeTheme, busy: picker.busy});
        }
    }
    PanelWindow {
        id: window
        screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0]
        implicitWidth: Math.min(1080, screen.width - 64)
        implicitHeight: Math.min(740, screen.height - 80)
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "quickshell:themePicker"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        ThemePickerContent {
            id: picker
            anchors.fill: parent
            onCloseRequested: {
                if (busy) window.visible = false;
                else Qt.quit();
            }
            onOperationFinished: { if (!window.visible) Qt.quit(); }
        }
    }
}
