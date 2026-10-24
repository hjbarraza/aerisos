import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons

// The pill dock: running apps, icons from the Mono theme. Hidden by sliding below the
// screen edge. Autohide is pointer-driven inside the shell (no cursor polling): a 1 px
// strip along the bottom edge reveals it, leaving the pill (plus a small halo) hides it.
Scope {
    id: dock
    property bool hidden: true
    readonly property int haloX: 48   // how far beside the pill still counts as "on it"
    readonly property int haloY: 24   // how far above
    readonly property int gap: 8      // pill to screen edge

    // Reveal: the bottom edge. Only exists while the dock is hidden.
    PanelWindow {
        visible: Theme.dockEnabled && dock.hidden
        anchors { bottom: true; left: true; right: true }
        implicitHeight: 1
        exclusiveZone: 0
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "aeris-dock-edge"
        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onEntered: { dock.hidden = false; leaveTimer.restart() }
        }
    }

    // The dock itself: pill at the bottom, a transparent halo around it for the hover test
    PanelWindow {
        id: win
        visible: Theme.dockEnabled
        anchors.bottom: true
        margins.bottom: dock.hidden ? -(implicitHeight + 4) : 0
        implicitWidth: pill.width + 2 * dock.haloX
        implicitHeight: pill.height + dock.gap + dock.haloY
        exclusiveZone: 0
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "aeris-dock"

        // Revealed from the edge but never entered (pointer far from the pill): fold back
        Timer { id: leaveTimer; interval: 1500; onTriggered: dock.hidden = true }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onEntered: leaveTimer.stop()
            onExited: leaveTimer.interval = 250, leaveTimer.restart()
        }

        Rectangle {
            id: pill
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: dock.gap
            width: row.width + 20
            height: 48
            radius: height / 2
            color: "#d9111111"
            border.color: "#40ffffff"
            border.width: 1
            clip: true

            // nothing running: fold up
            states: State {
                name: "empty"
                when: ToplevelManager.toplevels.values.length === 0
                PropertyChanges { target: pill; width: 1; height: 1; opacity: 0 }
            }

            Row {
                id: row
                anchors.centerIn: parent
                spacing: 4
                Repeater {
                    model: ToplevelManager.toplevels
                    delegate: Rectangle {
                        required property var modelData
                        width: 40; height: 40; radius: 10
                        color: modelData.activated ? "#30ffffff"
                             : mouse.containsMouse ? "#18ffffff" : "transparent"
                        Image {
                            anchors.centerIn: parent
                            width: 30; height: 30
                            fillMode: Image.PreserveAspectFit
                            sourceSize: Qt.size(96, 96)   // oversample: sharp at fractional scale
                            source: {
                                const entry = DesktopEntries.heuristicLookup(modelData.appId)
                                const icon = entry?.icon || modelData.appId || ""
                                const p = Quickshell.iconPath(icon, "application-x-executable")
                                return p ? p.toString() : ""
                            }
                        }
                        MouseArea {
                            id: mouse
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                            onClicked: event => {
                                if (event.button === Qt.MiddleButton) modelData.close()
                                else if (modelData.activated) modelData.minimized = true
                                else modelData.activate()
                            }
                        }
                    }
                }
            }
        }
    }
}
