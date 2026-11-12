// AERIS 3D wallpaper — quickshell 0.3.x + Qt Quick 3D. One full-screen Background layer per screen.
// Scene name in ~/.local/state/aeris-wallpaper/scene (watched): globe, particles, terrain, sky,
// decisions, constellation, or off. Change it with `aeris-wallpaper set NAME` or the bar menu.
// Frames: 30/s on AC, 15/s on battery, paused while the focused window is fullscreen.
// IPC: qs ipc -p <this file> call wallpaper set NAME | next
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.UPower

ShellRoot {
    id: root
    readonly property var names: ["globe", "particles", "terrain", "sky", "decisions", "constellation"]
    readonly property string stateFile: Quickshell.env("HOME") + "/.local/state/aeris-wallpaper/scene"
    property string scene: "decisions"
    property bool fullscreen: false
    property real t: 0
    readonly property bool onBattery: UPower.onBattery
    readonly property bool running: scene !== "off" && !fullscreen

    FileView {
        path: root.stateFile
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            const s = text().trim()
            root.scene = (s === "off" || root.names.indexOf(s) >= 0) ? s : "decisions"
        }
        onLoadFailed: root.scene = "decisions"
    }

    // One clock for every scene: they read root.t (seconds) and animate from it.
    Timer {
        interval: root.onBattery ? 66 : 33
        running: root.running
        repeat: true
        property real last: 0
        onRunningChanged: last = 0
        onTriggered: {
            const now = Date.now() / 1000
            root.t += last ? Math.min(0.1, now - last) : 0
            last = now
        }
    }

    // Pause behind fullscreen windows: re-check the focused window on Hyprland events.
    Process {
        id: fsProc
        command: ["hyprctl", "activewindow", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.fullscreen = (JSON.parse(text).fullscreen ?? 0) > 0 }
                catch (e) { root.fullscreen = false }
            }
        }
    }
    Connections {
        target: Hyprland
        function onRawEvent(ev) {
            if (["fullscreen", "activewindow", "workspace", "closewindow", "focusedmon"].indexOf(ev.name) >= 0)
                fsProc.running = true
        }
    }

    IpcHandler {
        target: "wallpaper"
        function set(name: string): void { root.scene = name }
        function next(): void { root.scene = root.names[(root.names.indexOf(root.scene) + 1) % root.names.length] }
    }

    Variants {
        model: Quickshell.screens
        PanelWindow {
            required property var modelData
            screen: modelData
            visible: root.scene !== "off"
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Background
            WlrLayershell.namespace: "aeris-wallpaper"
            color: "black"
            Loader {
                anchors.fill: parent
                active: root.scene !== "off"
                source: active ? "scenes/" + root.scene.charAt(0).toUpperCase() + root.scene.slice(1) + ".qml" : ""
                onLoaded: item.clock = Qt.binding(() => root.t)
            }
        }
    }
}
