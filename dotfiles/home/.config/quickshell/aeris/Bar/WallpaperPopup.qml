import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Commons
import qs.Ui

// Wallpaper menu under its bar icon: pick a 3D scene or turn the wallpaper off.
// Runs `aeris-wallpaper set NAME|off`; reads `aeris-wallpaper status` when it opens.
PopupWindow {
    id: wpPopup
    property Item anchorItem: null
    property string scene: ""
    property bool on: false
    readonly property var scenes: [
        ["globe", "Globe", "wireframe Earth, real day and night"],
        ["particles", "Particles", "points drifting toward you"],
        ["terrain", "Terrain", "flying over grey hills"],
        ["sky", "Sky", "clouds, and a distant dragon"],
        ["decisions", "Decisions", "a galaxy of branching choices"],
        ["constellation", "Constellation", "linked stars, slowly turning"]]

    anchor.rect.x: 0
    anchor.rect.y: Theme.barHeight
    implicitWidth: 260
    implicitHeight: wpCol.implicitHeight + 20
    visible: false
    color: "transparent"

    function open() {
        anchor.rect.x = anchorItem.mapToItem(null, 0, 0).x + anchorItem.width - implicitWidth
        statusProc.running = true
        visible = true
    }
    function toggle() { if (visible) visible = false; else open() }
    function act(c) { visible = false; Shell.sh(c); refreshTimer.restart() }

    Timer { id: refreshTimer; interval: 900; onTriggered: Shell.refreshTick++ }
    Process {
        id: statusProc
        command: ["sh", "-c", "~/.local/bin/aeris-wallpaper status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { const j = JSON.parse(text); wpPopup.scene = j.scene ?? ""; wpPopup.on = j.class === "on" }
                catch (e) { wpPopup.on = false }
            }
        }
    }
    HyprlandFocusGrab { windows: [wpPopup]; active: wpPopup.visible; onCleared: wpPopup.visible = false }

    Rectangle { anchors.fill: parent; color: Theme.bg; border.color: Theme.line; border.width: 1 }
    Column {
        id: wpCol
        x: 12; y: 10
        width: wpPopup.implicitWidth - 24
        spacing: 4
        Caption { text: "WALLPAPER" }
        Item { width: 1; height: 2 }
        Repeater {
            model: wpPopup.scenes
            RowLayout {
                id: row
                required property var modelData
                readonly property bool current: wpPopup.on && wpPopup.scene === modelData[0]
                width: wpCol.width
                spacing: 6
                Text { text: row.current ? "●" : "○"; color: row.current ? Theme.fg : Theme.dim; font.pixelSize: 8 }
                Text { text: row.modelData[1]; color: Theme.fg; font { family: Theme.sans; pixelSize: Theme.size } }
                Text {
                    text: row.modelData[2]; color: Theme.dim; elide: Text.ElideRight
                    font { family: Theme.sans; pixelSize: Theme.small }
                    Layout.fillWidth: true
                }
                TapHandler { onTapped: wpPopup.act("aeris-wallpaper set " + row.modelData[0]) }
            }
        }
        Item { width: 1; height: 3 }
        Rectangle { width: parent.width; height: 1; color: Theme.line }
        Item { width: 1; height: 2 }
        Caption {
            text: wpPopup.on ? "OFF" : "ON"
            TapHandler { onTapped: wpPopup.act(wpPopup.on ? "aeris-wallpaper off" : "aeris-wallpaper set " + (wpPopup.scene && wpPopup.scene !== "off" ? wpPopup.scene : "decisions")) }
        }
    }
}
