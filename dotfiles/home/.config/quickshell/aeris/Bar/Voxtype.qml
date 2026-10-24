import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui

// Dictation state, streamed from `voxtype status --follow` (one long-lived process).
Glyph {
    id: vox
    property string state: "stopped"
    readonly property var icons: ({ idle: "\u{F036C}", recording: "\u{F036C}", transcribing: "\u{F036C}…", stopped: "\u{F036D}" })
    text: icons[state] ?? ""
    color: state === "recording" ? Theme.warn
         : state === "transcribing" ? Theme.fg : Theme.dim
    Process {
        command: ["voxtype", "status", "--follow", "--format", "json"]
        running: true
        stdout: SplitParser {
            onRead: line => {
                try { vox.state = JSON.parse(line).alt ?? "stopped" } catch (e) {}
            }
        }
    }
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: ev => ev.button === Qt.RightButton
            ? Shell.sh("systemctl --user restart voxtype")
            : Shell.sh("ghostty -e voxtype configure")
    }
}
