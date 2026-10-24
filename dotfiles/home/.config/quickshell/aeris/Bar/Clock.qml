import QtQuick
import Quickshell
import qs.Commons

// Weekday and time; right-click shows the date, ISO week and year instead.
Text {
    property bool alt: false
    SystemClock { id: clock; precision: SystemClock.Minutes }
    text: alt ? Qt.formatDateTime(clock.date, "dd MMMM") + "  W" + Shell.isoWeek(clock.date) + " " + Qt.formatDateTime(clock.date, "yyyy")
              : Qt.formatDateTime(clock.date, "dddd HH:mm")
    color: Theme.fg
    font { family: Theme.sans; pixelSize: Theme.size }
    leftPadding: 7
    rightPadding: 7
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.RightButton
        onClicked: parent.alt = !parent.alt
    }
}
