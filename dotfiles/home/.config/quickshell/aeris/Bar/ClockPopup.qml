import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Commons
import qs.Ui

// World clock dropdown under the bar's clock: full date + ISO week at the top, followed by
// Tijuana, CDMX, New York, London and Paris (with yesterday/tomorrow when on another date),
// and a TIMEZONE ↗ action to change the system timezone (`tz-select`).
PopupWindow {
    id: clockPopup
    property Item anchorItem: null
    property string header: ""
    property var rows: []

    anchor.rect.x: 0
    anchor.rect.y: Theme.barHeight
    implicitWidth: 260
    implicitHeight: clockCol.implicitHeight + 20
    visible: false
    color: "transparent"

    function open() {
        anchor.rect.x = Math.round(anchorItem.mapToItem(null, 0, 0).x + (anchorItem.width - implicitWidth) / 2)
        tzProc.running = true
        visible = true
    }
    function toggle() { if (visible) visible = false; else open() }

    Process {
        id: tzProc
        command: ["bash", "-c",
            "today=$(date +%Y%m%d); " +
            "LC_ALL=C date '+%A %d %B %Y  ·  week %V'; " +
            "for p in 'America/Tijuana|Tijuana' 'America/Mexico_City|CDMX' 'America/New_York|New York' 'Europe/London|London' 'Europe/Paris|Paris'; do " +
            "  z=${p%%|*}; n=${p#*|}; there=$(TZ=$z date +%Y%m%d); d=''; " +
            "  (( there > today )) && d='tomorrow'; (( there < today )) && d='yesterday'; " +
            "  printf '%s\\t%s\\t%s\\n' \"$(TZ=$z date +%H:%M)\" \"$n\" \"$d\"; " +
            "done"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n")
                clockPopup.header = lines[0] ?? ""
                clockPopup.rows = lines.slice(1).filter(l => l.length > 0).map(l => {
                    const p = l.split("\t")
                    return { time: p[0] ?? "", city: p[1] ?? "", day: p[2] ?? "" }
                })
            }
        }
    }
    Timer {
        interval: 15000
        running: clockPopup.visible
        repeat: true
        onTriggered: tzProc.running = true
    }
    HyprlandFocusGrab { windows: [clockPopup]; active: clockPopup.visible; onCleared: clockPopup.visible = false }

    Rectangle { anchors.fill: parent; color: Theme.bg; border.color: Theme.line; border.width: 1 }
    Column {
        id: clockCol
        x: 14; y: 10
        width: clockPopup.implicitWidth - 28
        spacing: 5
        Text {
            text: clockPopup.header
            color: Theme.dim
            font { family: Theme.sans; pixelSize: Theme.small }
        }
        Item { width: 1; height: 2 }
        Repeater {
            model: clockPopup.rows
            RowLayout {
                id: cityRow
                required property var modelData
                width: clockCol.width
                spacing: 12
                Text {
                    text: cityRow.modelData.time
                    color: Theme.fg
                    font { family: Theme.sans; pixelSize: Theme.size; bold: true }
                }
                Text {
                    text: cityRow.modelData.city
                    color: Theme.fg
                    font { family: Theme.sans; pixelSize: Theme.size }
                }
                Text {
                    visible: cityRow.modelData.day !== ""
                    text: "·  " + cityRow.modelData.day
                    color: Theme.dim
                    font { family: Theme.sans; pixelSize: Theme.small }
                }
                Item { Layout.fillWidth: true }
            }
        }
        Item { width: 1; height: 3 }
        Rectangle { width: parent.width; height: 1; color: Theme.line }
        Item { width: 1; height: 2 }
        RowLayout {
            width: parent.width
            Caption {
                text: "TIMEZONE ↗"
                color: Theme.dim
                TapHandler {
                    onTapped: {
                        clockPopup.visible = false
                        Shell.sh("ghostty --class=aeris.tui-float -e ~/.local/bin/tz-select")
                    }
                }
            }
            Item { Layout.fillWidth: true }
        }
    }
}
