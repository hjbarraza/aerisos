import QtQuick
import Quickshell.Io
import qs.Commons

// A Waybar-style module: runs `cmd` and expects {"text", "class", "tooltip"} JSON.
// Re-runs when a command pushes `aeris-shell bar refresh` (Shell.refreshTick), after a
// click, and every `interval` ms while `active` (0 = never; set `active` to the drawer's
// open state for things nobody sees while it is closed).
Text {
    id: mod
    property list<string> cmd
    property int interval: 0
    property bool active: true
    property var onClick: null
    property var onRightClick: null
    property string klass: ""

    color: (klass === "off" || klass === "disconnected") ? Theme.dim : Theme.fg
    font.family: Theme.nerd
    font.pixelSize: Theme.size
    visible: text !== ""
    leftPadding: visible ? 7 : 0
    rightPadding: visible ? 8 : 0

    function refresh() { proc.running = true }

    property int _tick: Shell.refreshTick
    on_TickChanged: refresh()
    onActiveChanged: if (active) refresh()

    Process {
        id: proc
        command: mod.cmd
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const j = JSON.parse(text.trim() || "{}")
                    mod.text = j.text ?? ""
                    mod.klass = j.class ?? ""   // "off" renders dim (e.g. Stay Awake)
                } catch (e) { mod.text = "" }
            }
        }
    }
    Timer {
        interval: mod.interval
        running: mod.interval > 0 && mod.active
        repeat: true
        onTriggered: mod.refresh()
    }
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: ev => {
            const f = ev.button === Qt.RightButton ? mod.onRightClick : mod.onClick
            if (f) { f(); Qt.callLater(mod.refresh) }
        }
    }
}
