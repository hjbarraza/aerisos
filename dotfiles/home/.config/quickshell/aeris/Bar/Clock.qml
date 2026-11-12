import QtQuick
import Quickshell
import qs.Commons

// Weekday and time; click opens the world clock dropdown, right-click shows the date, ISO
// week and year inline instead.
Text {
    id: clockText
    property bool alt: false
    property var onClick: null
    SystemClock { id: clock; precision: SystemClock.Minutes }
    text: alt ? Qt.formatDateTime(clock.date, "dd MMMM") + "  W" + Shell.isoWeek(clock.date) + " " + Qt.formatDateTime(clock.date, "yyyy")
              : Qt.formatDateTime(clock.date, "dddd HH:mm")
    color: Theme.fg
    font { family: Theme.sans; pixelSize: Theme.size }
    leftPadding: 7
    rightPadding: 7
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: ev => {
            if (ev.button === Qt.RightButton) clockText.alt = !clockText.alt
            else if (clockText.onClick) clockText.onClick()
        }
    }
}
