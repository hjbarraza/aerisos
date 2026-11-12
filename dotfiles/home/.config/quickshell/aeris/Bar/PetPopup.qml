import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Commons
import qs.Ui

// Pet menu under the paw icon: pick the pet (dragon, raven), where it lives (the desktop
// overlay or a strip of the bar, PetLane), show or hide it. Also opened by right-clicking
// the pet itself (`aeris-shell pet menu` from the overlay). Reads `aeris-pet status` on open.
PopupWindow {
    id: petPopup
    property Item anchorItem: null
    property string pet: ""
    property bool running: false
    property string where: "desktop"
    readonly property var pets: [["dragon", "Dragon"], ["raven", "Raven"]]
    readonly property var places: [["desktop", "On desktop"], ["bar", "In bar"]]

    anchor.rect.x: 0
    anchor.rect.y: Theme.barHeight
    implicitWidth: 168
    implicitHeight: petCol.implicitHeight + 20
    visible: false
    color: "transparent"

    // atX: open under that bar x (the roaming pet) instead of under the paw
    function open(atX) {
        anchor.rect.x = atX !== undefined
            ? Math.max(4, atX - implicitWidth / 2)
            : anchorItem.mapToItem(null, 0, 0).x + anchorItem.width - implicitWidth
        statusProc.running = true
        visible = true
    }
    function toggle() { if (visible) visible = false; else open() }
    function act(c) {
        visible = false
        Shell.sh(c)
        refreshTimer.restart()
    }

    Timer { id: refreshTimer; interval: 900; onTriggered: Shell.refreshTick++ }

    Process {
        id: statusProc
        command: ["sh", "-c", "~/.local/bin/aeris-pet status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const j = JSON.parse(text)
                    petPopup.pet = j.pet ?? ""
                    petPopup.running = j.running === true
                    petPopup.where = j.where ?? "desktop"
                } catch (e) { petPopup.running = false }
            }
        }
    }
    HyprlandFocusGrab { windows: [petPopup]; active: petPopup.visible; onCleared: petPopup.visible = false }

    Rectangle { anchors.fill: parent; color: Theme.bg; border.color: Theme.line; border.width: 1 }
    Column {
        id: petCol
        x: 12; y: 10
        width: petPopup.implicitWidth - 24
        spacing: 4
        Caption { text: "PET" }
        Item { width: 1; height: 2 }
        Repeater {
            model: petPopup.pets
            RowLayout {
                id: petRow
                required property var modelData
                readonly property bool current: petPopup.pet === modelData[0]
                width: petCol.width
                spacing: 6
                Text {
                    text: petRow.current ? "●" : "○"
                    color: petRow.current && petPopup.running ? Theme.fg : Theme.dim
                    font.pixelSize: 8
                }
                Text {
                    text: petRow.modelData[1]
                    color: Theme.fg
                    font { family: Theme.sans; pixelSize: Theme.size }
                    Layout.fillWidth: true
                }
                TapHandler { onTapped: petPopup.act("aeris-pet set " + petRow.modelData[0]) }
            }
        }
        Item { width: 1; height: 3 }
        Rectangle { width: parent.width; height: 1; color: Theme.line }
        Item { width: 1; height: 2 }
        Repeater {
            model: petPopup.places
            RowLayout {
                id: placeRow
                required property var modelData
                readonly property bool current: petPopup.where === modelData[0]
                width: petCol.width
                spacing: 6
                Text {
                    text: placeRow.current ? "●" : "○"
                    color: placeRow.current ? Theme.fg : Theme.dim
                    font.pixelSize: 8
                }
                Text {
                    text: placeRow.modelData[1]
                    color: Theme.fg
                    font { family: Theme.sans; pixelSize: Theme.size }
                    Layout.fillWidth: true
                }
                TapHandler { onTapped: petPopup.act("aeris-pet where " + placeRow.modelData[0]) }
            }
        }
        Item { width: 1; height: 3 }
        Rectangle { width: parent.width; height: 1; color: Theme.line }
        Item { width: 1; height: 2 }
        Caption {
            text: petPopup.running ? "QUIT" : "SHOW"
            TapHandler { onTapped: petPopup.act(petPopup.running ? "aeris-pet quit" : "aeris-pet start") }
        }
    }
}
