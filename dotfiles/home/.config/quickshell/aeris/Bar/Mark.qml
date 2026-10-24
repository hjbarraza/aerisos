import QtQuick
import qs.Commons

// The Æ mark: opens the AerisOS menu.
Text {
    text: "Æ"
    color: "#ffffff"
    font { family: Theme.sans; weight: Font.Bold; pixelSize: Theme.size + 3 }
    rightPadding: 10
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: Shell.sh("~/.local/bin/aeris-menu")
    }
}
