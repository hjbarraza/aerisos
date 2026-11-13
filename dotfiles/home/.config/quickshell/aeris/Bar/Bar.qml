import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
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
            id: content
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 16

            RowLayout {   // ---- left: Æ mark + workspaces
                id: leftGroup
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
                onClick: () => clockPopup.toggle()
            }
            RowLayout {   // ---- hangs left of the clock: toggles
                id: togglesGroup
                anchors.right: clock.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 0
                Toggles {}
            }
            RowLayout {   // ---- hangs right of the clock: dictation, AERIS alerts
                id: alertsGroup
                anchors.left: clock.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 0
                Voxtype {}
                Alerts {}
            }

            RowLayout {   // ---- right: wallpaper, pet, tailscale, note, network, audio, mouse, battery, drawer
                id: rightGroup
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 0
                Wallpaper {
                    id: wpIcon
                    onClick: () => wpPopup.toggle()
                }
                Pet {
                    id: petIcon
                    onClick: () => petPopup.toggle()
                }
                Tailscale {
                    id: tsIcon
                    onClick: () => tsPopup.toggle()
                    onRightClick: () => Shell.sh("~/.local/bin/tailscale-status admin")
                }
                Note {
                    id: noteIcon
                    onClick: () => notePopup.toggle()
                }
                Network {}
                Volume {}
                Mouse {}
                Battery {}
                Drawer { barWindow: bar }
            }
        }
    }

    // Where the icons are, in bar x: what the roaming pet (PetLane) must keep clear of.
    function obstacles() {
        const out = []
        const add = it => {
            if (!it.visible || it.width <= 0) return
            const p = it.mapToItem(null, 0, 0)
            out.push([p.x, p.x + it.width])
        }
        for (const g of [leftGroup, togglesGroup, alertsGroup, rightGroup])
            for (const c of g.children) add(c)
        add(clock)
        return out
    }

    // The pet in bar mode, on its own layer over the bar (`aeris-pet where bar`)
    PetLane {
        visible: Shell.barShown && petIcon.inBar
        kind: petIcon.kind
        obstacles: () => root.obstacles()
        onRightClick: x => petPopup.open(x)
    }

    TailscalePopup {
        id: tsPopup
        anchor.window: bar
        anchorItem: tsIcon
    }

    PetPopup {
        id: petPopup
        anchor.window: bar
        anchorItem: petIcon
    }

    WallpaperPopup {
        id: wpPopup
        anchor.window: bar
        anchorItem: wpIcon
    }

    NotePopup {
        id: notePopup
        anchor.window: bar
        anchorItem: noteIcon
    }

    ClockPopup {
        id: clockPopup
        anchor.window: bar
        anchorItem: clock
    }

    // `aeris-shell pet menu`: the pet's right click opens this menu
    IpcHandler {
        target: "pet"
        function menu(): void { if (Shell.barShown) petPopup.open() }
    }
}
