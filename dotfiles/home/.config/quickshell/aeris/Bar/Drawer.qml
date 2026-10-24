import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import qs.Commons
import qs.Ui

// The 󰅁 drawer at the right end: system tray, bluetooth, backlight, cpu, power profile.
// Everything behind it only polls while it is open.
RowLayout {
    id: drawer
    required property var barWindow
    property bool open: false
    spacing: 0

    Glyph {
        text: drawer.open ? "󰅂" : "󰅁"
        color: Theme.dim
        leftPadding: 4; rightPadding: 6
        MouseArea { anchors.fill: parent; onClicked: drawer.open = !drawer.open }
    }
    RowLayout {
        spacing: 0
        visible: drawer.open

        Repeater {   // system tray
            model: SystemTray.items
            Item {
                id: trayItem
                required property var modelData
                implicitWidth: 24; implicitHeight: 16
                IconImage {
                    anchors.centerIn: parent
                    implicitSize: 12
                    source: trayItem.modelData.icon
                }
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: ev => {
                        // menu-only items have no activate action: ones that say so
                        // (LocalSend) and ayatana items that only carry a menu (nm-applet)
                        const menuOnly = trayItem.modelData.onlyMenu ||
                                         trayItem.modelData.id === "nm-applet"
                        if (trayItem.modelData.hasMenu &&
                            (ev.button === Qt.RightButton || menuOnly))
                            menuAnchor.open()
                        else trayItem.modelData.activate()
                    }
                }
                QsMenuAnchor {
                    id: menuAnchor
                    menu: trayItem.modelData.menu
                    anchor.window: drawer.barWindow
                    anchor.rect.x: trayItem.mapToItem(null, 0, 0).x
                    anchor.rect.y: Theme.barHeight
                }
            }
        }
        StatusModule {   // bluetooth
            cmd: ["sh", "-c",
                "if ! bluetoothctl show 2>/dev/null | grep -q 'Powered: yes'; then echo '{\"text\":\"󰂲\"}'; " +
                "elif [ \"$(bluetoothctl devices Connected 2>/dev/null | wc -l)\" -gt 0 ]; then echo '{\"text\":\"󰂱\"}'; " +
                "else echo '{\"text\":\"󰂯\"}'; fi"]
            interval: 10000
            active: drawer.open
            onClick: () => Shell.sh("ghostty --class=aeris.tui-float -e bluetui")
        }
        Glyph {   // backlight
            id: backlight
            property int pct: -1
            visible: pct >= 0
            text: pct > 66 ? "󰃠" : pct > 33 ? "󰃟" : "󰃞"
            Process {
                id: blProc
                command: ["sh", "-c", "brightnessctl -m 2>/dev/null | cut -d, -f4 | tr -d %"]
                running: true
                stdout: StdioCollector {
                    onStreamFinished: backlight.pct = text.trim() === "" ? -1 : parseInt(text.trim())
                }
            }
            Timer { interval: 5000; running: drawer.open; repeat: true; onTriggered: blProc.running = true }
            MouseArea {
                anchors.fill: parent
                onWheel: w => {
                    Shell.sh("brightnessctl -e4 -n2 set 5%" + (w.angleDelta.y > 0 ? "+" : "-"))
                    Qt.callLater(() => blProc.running = true)
                }
            }
        }
        Glyph {   // cpu
            text: "󰍛"
            MouseArea { anchors.fill: parent; onClicked: Shell.sh("command -v btop >/dev/null && ghostty -e btop || ghostty -e top") }
        }
        StatusModule {   // power profile; click cycles
            cmd: ["sh", "-c",
                "p=$(powerprofilesctl get 2>/dev/null); case $p in performance) echo '{\"text\":\"\"}';; " +
                "power-saver) echo '{\"text\":\"\"}';; balanced) echo '{\"text\":\"\"}';; *) echo '{\"text\":\"\"}';; esac"]
            interval: 10000
            active: drawer.open
            onClick: () => Shell.sh(
                "p=$(powerprofilesctl get); case $p in balanced) n=performance;; performance) n=power-saver;; *) n=balanced;; esac; powerprofilesctl set $n")
        }
    }
}
