import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui

// The paw icon and the pet's state from `aeris-pet status`. Desktop mode: the paw (dim while
// the overlay pet is hidden). Bar mode (`aeris-pet where bar`): the paw steps aside (width 0)
// and Bar.qml shows PetLane, the pet roaming the bar; hidden in bar mode shows the dim paw
// again so the menu stays reachable. Left click on the paw: onClick (the PetPopup menu).
// `aeris-pet` pushes a bar refresh whenever the choice, place or visibility changes.
Item {
    id: pet
    property var onClick: null
    property string kind: "dragon"
    property string where: "desktop"
    property bool running: false
    readonly property bool inBar: where === "bar" && running

    implicitWidth: inBar ? 0 : paw.implicitWidth
    implicitHeight: Theme.barHeight

    function refresh() { proc.running = true }
    property int _tick: Shell.refreshTick
    on_TickChanged: refresh()

    Process {
        id: proc
        command: ["sh", "-c", "~/.local/bin/aeris-pet status"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const j = JSON.parse(text.trim() || "{}")
                    paw.text = j.text ?? ""
                    pet.kind = j.pet ?? "dragon"
                    pet.where = j.where ?? "desktop"
                    pet.running = j.running === true
                } catch (e) { paw.text = "" }
            }
        }
    }
    // Fallback for the overlay dying without its exit refresh (killed, crashed).
    Timer { interval: 60000; running: true; repeat: true; onTriggered: pet.refresh() }

    Text {
        id: paw
        visible: !pet.inBar && text !== ""
        anchors.verticalCenter: parent.verticalCenter
        color: pet.running ? Theme.fg : Theme.dim
        font.family: Theme.nerd
        font.pixelSize: Theme.size
        leftPadding: 7
        rightPadding: 8
        MouseArea {
            anchors.fill: parent
            onClicked: { if (pet.onClick) pet.onClick(); Qt.callLater(pet.refresh) }
        }
    }
}
