import QtQuick
import Quickshell.Services.UPower
import qs.Commons
import qs.Ui

// Wireless mouse battery (the MX Master over Bluetooth or a Logitech receiver), via UPower:
// events, no polling. Hidden while no mouse reports a battery. Click toggles the percentage;
// it shows by itself at 15% and below.
Glyph {
    readonly property var dev: {
        const all = UPower.devices.values
        for (let i = 0; i < all.length; i++)
            if (all[i].type === UPowerDeviceType.Mouse && all[i].isPresent !== false) return all[i]
        return null
    }
    readonly property real pct: (dev?.percentage ?? 0) * 100
    property bool showPct: false
    visible: dev !== null
    text: "󰍽" + (showPct || pct <= 15 ? " " + Math.round(pct) + "%" : "")
    color: pct <= 15 ? Theme.warn : Theme.fg
    MouseArea { anchors.fill: parent; onClicked: parent.showPct = !parent.showPct }
}
