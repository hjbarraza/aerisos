import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

// Two pills from the Status singleton. AIRSPACE: inverted for notable events (jamming,
// squawk, ISS/CSS overhead), outlined when only bright satellites are up. ALERTS: everything
// else (storms, outages), inverted as on the lock and login screens. Left click opens the
// orbit popup (aeris-orbit), right click the plain-text alert list. STALE: the collector
// has stopped writing.
RowLayout {
    spacing: 0

    component Pill: Rectangle {
        property string label: ""
        property bool hot: true
        visible: label !== ""
        color: hot ? "#ffffff" : "transparent"; radius: 3
        border { width: hot ? 0 : 1; color: Theme.fg }
        implicitWidth: pillText.implicitWidth + 12
        implicitHeight: 16
        Caption {
            id: pillText
            anchors.centerIn: parent
            text: parent.label
            color: parent.hot ? "#000000" : Theme.fg
        }
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: ev => Shell.sh(ev.button === Qt.RightButton
                ? "ghostty --class=aeris.tui-float -e ~/.local/bin/aeris-alerts"
                : "~/.local/bin/aeris-orbit")
        }
    }

    Pill { label: Status.labels.join(" · ") }
    Item { width: 6; visible: Status.labels.length > 0 && Status.airLabels.length > 0 }
    Pill { label: Status.airLabels.join(" · "); hot: Status.airHot.length > 0 }
    Caption {
        visible: Status.stale
        text: "STALE"
        color: Theme.dim
        leftPadding: 7; rightPadding: 8
    }
}
