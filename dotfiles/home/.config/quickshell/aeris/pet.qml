import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import "Bar"

// Standalone bar pet, for machines whose bar is Waybar (the Chromebook edition):
//   qs -p ~/.config/quickshell/aeris/pet.qml
// Runs only Bar/PetLane.qml (plus the PetPopup menu on right click), no bar or dock.
// Waybar cannot say where its icons are, so the no-go zones come from
// ~/.config/aeris/pet.json (watched), in px:
//   { "left": 75, "center": 95, "right": 231 }
// left = width of Waybar's left group, center = half-width kept clear around the screen
// middle, right = width of the right group. Bar height comes from shell.json (bar.height).
// `aeris-pet` pings `qs ipc -p <this file> call pet refresh` when the choice changes.
ShellRoot {
    id: root
    property string kind: "dragon"
    property bool inBar: false
    property var zones: ({ left: 0, center: 0, right: 0 })

    function refresh() { proc.running = true }

    Process {
        id: proc
        command: ["sh", "-c", "~/.local/bin/aeris-pet status"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const j = JSON.parse(text.trim() || "{}")
                    root.kind = j.pet ?? "dragon"
                    root.inBar = j.where === "bar" && j.running === true
                } catch (e) { root.inBar = false }
            }
        }
    }
    IpcHandler {
        target: "pet"
        function refresh(): void { root.refresh() }
    }
    Connections {   // PetPopup bumps refreshTick after a menu action
        target: Shell
        function onRefreshTickChanged() { root.refresh() }
    }

    FileView {
        path: Quickshell.env("HOME") + "/.config/aeris/pet.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const j = JSON.parse(text())
                root.zones = { left: j.left ?? 0, center: j.center ?? 0, right: j.right ?? 0 }
            } catch (e) { console.warn("pet.json: not valid JSON:", e) }
        }
    }

    PetLane {
        id: lane
        // Overlay keeps it above Waybar after Waybar reloads; Overlay is also above
        // fullscreen windows, so it steps away while the workspace has one.
        layer: WlrLayer.Overlay
        visible: root.inBar && !(Hyprland.focusedMonitor?.activeWorkspace?.hasFullscreen ?? false)
        kind: root.kind
        obstacles: () => {
            const z = root.zones, w = lane.width, out = []
            if (z.left > 0) out.push([0, z.left])
            if (z.center > 0) out.push([w / 2 - z.center, w / 2 + z.center])
            if (z.right > 0) out.push([w - z.right, w])
            return out
        }
        onRightClick: x => menu.open(x)
    }
    PetPopup {
        id: menu
        anchor.window: lane
        anchorItem: null
    }
}
