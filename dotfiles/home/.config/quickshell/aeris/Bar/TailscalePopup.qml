import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Commons
import qs.Ui

// Tailscale submenu under the bar icon: devices with online dots (click a row to copy
// its IP), connect/disconnect, admin console. Reads `tailscale status --json` when it
// opens (the user is the tailscale operator).
PopupWindow {
    id: tsPopup
    property Item anchorItem: null
    property string backend: ""
    property var rows: []
    property string copied: ""

    // mapToItem has no change signal, so a plain binding goes stale (menu far left):
    // the position is computed when the menu opens.
    anchor.rect.x: 0
    anchor.rect.y: Theme.barHeight
    implicitWidth: 252
    implicitHeight: tsCol.implicitHeight + 20
    visible: false
    color: "transparent"

    function toggle() {
        if (visible) visible = false
        else {
            anchor.rect.x = anchorItem.mapToItem(null, 0, 0).x + anchorItem.width - implicitWidth
            tsProc.running = true; visible = true
        }
    }
    function act(c) { Shell.sh(c); actTimer.restart() }

    Timer { id: actTimer; interval: 800; onTriggered: { tsProc.running = true; Shell.refreshTick++ } }
    Timer { id: copyTimer; interval: 1500; onTriggered: tsPopup.copied = "" }

    Process {
        id: tsProc
        command: ["tailscale", "status", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const j = JSON.parse(text)
                    tsPopup.backend = j.BackendState ?? ""
                    const mk = (p, self) => ({
                        // iOS devices report HostName "localhost": use the DNS name
                        host: (!p.HostName || p.HostName === "localhost")
                              ? (p.DNSName ?? "?").split(".")[0] : p.HostName,
                        ip: (p.TailscaleIPs ?? [""])[0] ?? "",
                        online: self ? true : p.Online === true,
                        self: self })
                    const peers = Object.values(j.Peer ?? {}).map(p => mk(p, false))
                    peers.sort((a, b) => (b.online - a.online) || a.host.localeCompare(b.host))
                    tsPopup.rows = (j.Self ? [mk(j.Self, true)] : []).concat(peers)
                } catch (e) { tsPopup.backend = "Off"; tsPopup.rows = [] }
            }
        }
    }
    HyprlandFocusGrab { windows: [tsPopup]; active: tsPopup.visible; onCleared: tsPopup.visible = false }

    Rectangle { anchors.fill: parent; color: Theme.bg; border.color: Theme.line; border.width: 1 }
    Column {
        id: tsCol
        x: 12; y: 10
        width: tsPopup.implicitWidth - 24
        spacing: 3
        RowLayout {
            width: parent.width
            Caption { text: "TAILSCALE" }
            Item { Layout.fillWidth: true }
            Caption {
                text: tsPopup.backend === "Running" ? "CONNECTED"
                    : tsPopup.backend === "Stopped" ? "DISCONNECTED"
                    : tsPopup.backend === "NeedsLogin" ? "NEEDS LOGIN" : tsPopup.backend.toUpperCase()
                color: tsPopup.backend === "Running" ? Theme.fg : Theme.dim
            }
        }
        Item { width: 1; height: 3 }
        Repeater {
            model: tsPopup.rows
            RowLayout {
                id: tsRow
                required property var modelData
                width: tsCol.width
                spacing: 6
                Text { text: tsRow.modelData.online ? "●" : "○"
                    color: tsRow.modelData.online ? Theme.fg : Theme.dim
                    font.pixelSize: 8 }
                Text {
                    text: tsRow.modelData.host + (tsRow.modelData.self ? " · this" : "")
                    color: tsRow.modelData.online ? Theme.fg : Theme.dim
                    font { family: Theme.sans; pixelSize: Theme.size }
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
                Text {
                    text: tsPopup.copied === tsRow.modelData.ip ? "copied" : tsRow.modelData.ip
                    color: Theme.dim
                    font { family: Theme.sans; pixelSize: Theme.small }
                }
                // Click anywhere on the row to copy the device's Tailscale IP
                TapHandler {
                    onTapped: {
                        Shell.sh("wl-copy " + tsRow.modelData.ip)
                        tsPopup.copied = tsRow.modelData.ip
                        copyTimer.restart()
                    }
                }
            }
        }
        Item { width: 1; height: 4 }
        Rectangle { width: parent.width; height: 1; color: Theme.line }
        Item { width: 1; height: 2 }
        RowLayout {
            width: parent.width
            Caption {
                text: tsPopup.backend === "Running" ? "DISCONNECT" : "CONNECT"
                TapHandler { onTapped: tsPopup.act(tsPopup.backend === "Running" ? "tailscale down" : "tailscale up") }
            }
            Item { Layout.fillWidth: true }
            Caption {
                text: "ADMIN ↗"
                color: Theme.dim
                TapHandler { onTapped: { tsPopup.visible = false; Shell.sh("~/.local/bin/tailscale-status admin") } }
            }
        }
    }
}
