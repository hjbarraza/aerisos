import QtQuick
import qs.Ui

// The scratch note's bar icon; the bar opens NotePopup on click.
Glyph {
    id: icon
    property var onClick: null
    text: "󰎞"
    MouseArea { anchors.fill: parent; onClicked: if (icon.onClick) icon.onClick() }
}
