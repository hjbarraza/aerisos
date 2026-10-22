// AerisOS pill dock — quickshell 0.3.x
// Floating bottom pill listing running apps, icons from the user's GTK icon
// theme (Mono by default). Hidden by default; dock-autohide drives it via IPC:
//   qs ipc call dock show   /   qs ipc call dock hide
//@ pragma IconTheme Mono
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io

ShellRoot {
    PanelWindow {
        id: win
        visible: true
        // hidden by sliding below the screen edge (no unmap/map lifecycle races);
        // dock-autohide drives: qs ipc call dock show|hide|toggle
        property bool hidden: true
        anchors.bottom: true
        margins.bottom: hidden ? -64 : 8
        implicitWidth: pill.width
        implicitHeight: 52
        exclusiveZone: 0
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Top

        Rectangle {
            id: pill
            anchors.verticalCenter: parent.verticalCenter
            width: row.width + 20
            height: 48
            radius: height / 2
            color: "#d9111111"
            border.color: "#40ffffff"
            border.width: 1
            clip: true

            // empty state: nothing to show, fold up
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
                        width: 40
                        height: 40
                        radius: 10
                        color: modelData.activated ? "#30ffffff"
                             : mouse.containsMouse ? "#18ffffff" : "transparent"

                        Image {
                            anchors.centerIn: parent
                            width: 30
                            height: 30
                            fillMode: Image.PreserveAspectFit
                            // oversample so icons stay sharp at fractional 1.6x
                            sourceSize: Qt.size(96, 96)
                            source: {
                                const entry = DesktopEntries.heuristicLookup(modelData.appId);
                                const icon = entry?.icon || modelData.appId || "";
                                const p = Quickshell.iconPath(icon, "application-x-executable");
                                return p ? p.toString() : "";
                            }
                        }

                        MouseArea {
                            id: mouse
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                            onClicked: event => {
                                if (event.button === Qt.MiddleButton) {
                                    // close on middle click, like most docks
                                    modelData.close();
                                } else if (modelData.activated) {
                                    modelData.minimized = true;
                                } else {
                                    modelData.activate();
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // IPC endpoints for dock-autohide
    IpcHandler {
        target: "dock"
        // NB: avoid "show"/"hide" — reserved as qs ipc subcommands
        function reveal(): void { win.hidden = false }
        function conceal(): void { win.hidden = true }
        function flip(): void { win.hidden = !win.hidden }
    }
}
