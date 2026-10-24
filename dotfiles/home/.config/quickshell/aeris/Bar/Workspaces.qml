import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import qs.Commons

// Workspaces 1-5 always, any higher ones while they exist. Driven by Hyprland's events.
RowLayout {
    spacing: 0

    Repeater {
        model: 5
        Text {
            required property int index
            readonly property int ws: index + 1
            readonly property bool focused: (Hyprland.focusedWorkspace?.id ?? 1) === ws
            readonly property bool exists: Hyprland.workspaces.values.some(w => w.id === ws)
            text: focused ? "󱓻" : String(ws)
            color: focused ? "#ffffff" : (exists ? Theme.fg : Theme.dim)
            font { family: focused ? Theme.nerd : Theme.sans; pixelSize: Theme.size }
            leftPadding: 6; rightPadding: 6
            MouseArea { anchors.fill: parent; onClicked: Hyprland.dispatch("workspace " + parent.ws) }
        }
    }
    Repeater {
        model: ScriptModel { values: Hyprland.workspaces.values.filter(w => w.id > 5) }
        Text {
            required property var modelData
            readonly property bool focused: Hyprland.focusedWorkspace?.id === modelData.id
            text: focused ? "󱓻" : String(modelData.id % 10)
            color: focused ? "#ffffff" : Theme.fg
            font { family: focused ? Theme.nerd : Theme.sans; pixelSize: Theme.size }
            leftPadding: 6; rightPadding: 6
            MouseArea { anchors.fill: parent; onClicked: Hyprland.dispatch("workspace " + parent.modelData.id) }
        }
    }
}
