import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Commons
import qs.Ui

// Scratch note under its bar icon: one plain-text page kept in ~/.local/state/aeris/scratch.md,
// saved as you type (half a second after the last key) and reloaded if the file changes
// elsewhere. Esc or a click outside closes it. Inspired by the Omanote Omarchy plugin.
PopupWindow {
    id: notePopup
    property Item anchorItem: null
    readonly property string path: Quickshell.env("HOME") + "/.local/state/aeris/scratch.md"

    anchor.rect.x: 0
    anchor.rect.y: Theme.barHeight
    implicitWidth: 420
    implicitHeight: 320
    visible: false
    color: "transparent"

    function toggle() {
        if (visible) { save(); visible = false }
        else {
            anchor.rect.x = anchorItem.mapToItem(null, 0, 0).x + anchorItem.width - implicitWidth
            visible = true
            area.forceActiveFocus()
        }
    }
    function save() { if (area.text !== file.text()) file.setText(area.text) }

    Process { running: true; command: ["mkdir", "-p", Quickshell.env("HOME") + "/.local/state/aeris"] }
    FileView {
        id: file
        path: notePopup.path
        watchChanges: true
        printErrors: false
        onLoaded: if (!area.activeFocus) area.text = text()
        onFileChanged: reload()
    }
    Timer { id: saveTimer; interval: 500; onTriggered: notePopup.save() }
    HyprlandFocusGrab { windows: [notePopup]; active: notePopup.visible; onCleared: notePopup.toggle() }

    Rectangle { anchors.fill: parent; color: Theme.bg; border.color: Theme.line; border.width: 1 }
    Caption { x: 12; y: 10; text: "NOTE" }
    ScrollView {
        x: 12; y: 30
        width: notePopup.implicitWidth - 24
        height: notePopup.implicitHeight - 42
        TextArea {
            id: area
            color: Theme.fg
            selectionColor: Theme.fg
            selectedTextColor: Theme.bg
            font.family: Theme.sans
            font.pixelSize: Theme.size
            wrapMode: TextEdit.Wrap
            placeholderText: "scratch…"
            placeholderTextColor: Theme.dim
            background: null
            onTextChanged: saveTimer.restart()
            Keys.onEscapePressed: notePopup.toggle()
        }
    }
}
