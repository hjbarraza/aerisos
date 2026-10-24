import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui

// Connection type and Wi-Fi signal tier. `nmcli monitor` reports every connection change
// as it happens; the one-minute timer only follows signal strength, which sends no event.
Glyph {
    id: net
    property string icon: "󰤮"
    text: icon
    color: icon === "󰤮" ? Theme.dim : Theme.fg

    Process {
        id: netProc
        command: ["sh", "-c",
            "t=$(nmcli -t -f TYPE,STATE device | grep ':connected' | cut -d: -f1 | head -1); " +
            "if [ \"$t\" = wifi ]; then s=$(nmcli -t -f ACTIVE,SIGNAL device wifi | grep '^yes' | cut -d: -f2 | head -1); echo wifi ${s:-0}; " +
            "elif [ -n \"$t\" ]; then echo ethernet; else echo none; fi"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                const p = text.trim().split(" ")
                if (p[0] === "ethernet") net.icon = "󰀂"
                else if (p[0] === "wifi") {
                    const s = parseInt(p[1] ?? "0")
                    net.icon = s > 75 ? "󰤨" : s > 50 ? "󰤥" : s > 25 ? "󰤢" : "󰤟"
                } else net.icon = "󰤮"
            }
        }
    }
    Process {
        command: ["nmcli", "monitor"]
        running: true
        stdout: SplitParser { onRead: line => { if (!netProc.running) netProc.running = true } }
    }
    Timer { interval: 60000; running: true; repeat: true; onTriggered: netProc.running = true }
    MouseArea { anchors.fill: parent; onClicked: Shell.sh("ghostty --class=aeris.tui-float -e nmtui") }
}
