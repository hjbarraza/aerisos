// AerisOS backdrop: the desktop behind every window, a flat charcoal plane (#0a0a0a) on the
// background layer. Black windows sit on it with 8px gutters, so the Swiss grid shows.
// (Hyprland's misc.background_color does not repaint in a running session; this does.)
// Started from hyprland.lua:  qs -p ~/.config/quickshell/aeris/backdrop.qml
import QtQuick
import Quickshell
import Quickshell.Wayland

ShellRoot {
    Variants {
        model: Quickshell.screens
        PanelWindow {
            required property var modelData
            screen: modelData
            WlrLayershell.layer: WlrLayer.Background
            WlrLayershell.namespace: "aeris-backdrop"
            exclusionMode: ExclusionMode.Ignore
            anchors { top: true; bottom: true; left: true; right: true }
            color: "#0a0a0a"
        }
    }
}
