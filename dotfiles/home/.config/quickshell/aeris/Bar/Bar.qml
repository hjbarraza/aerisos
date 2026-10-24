import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// The top bar. Each widget is a file in this directory; order here is the order on screen.
Scope {
    id: root

    PanelWindow {
        id: bar
        visible: Shell.barShown
        anchors { top: true; left: true; right: true }
        implicitHeight: Theme.barHeight
        color: Theme.bg
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "aeris-bar"

        // Three groups: left and right hang off their edges; the clock sits on the exact
        // center of the screen with the toggles to its left and dictation + alerts to its
        // right, so it never drifts when a side group grows (the drawer opening, say).
        Item {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 16

            RowLayout {   // ---- left: Æ mark + workspaces
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 0
                Mark {}
                Workspaces {}
            }

            Clock {
                id: clock
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
            }
            RowLayout {   // ---- hangs left of the clock: toggles
                anchors.right: clock.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 0
                Toggles {}
            }
            RowLayout {   // ---- hangs right of the clock: dictation, AERIS alerts
                anchors.left: clock.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 0
                Voxtype {}
                Alerts {}
            }

            RowLayout {   // ---- right: tailscale, network, audio, battery, drawer
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 0
                Tailscale {
                    id: tsIcon
                    onClick: () => tsPopup.toggle()
                    onRightClick: () => Shell.sh("~/.local/bin/tailscale-status admin")
                }
                Network {}
                Volume {}
                Battery {}
                Drawer { barWindow: bar }
            }
        }
    }

    TailscalePopup {
        id: tsPopup
        anchor.window: bar
        anchorItem: tsIcon
    }
}
