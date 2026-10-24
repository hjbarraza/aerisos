import QtQuick
import Quickshell.Services.UPower
import qs.Commons
import qs.Ui

// Battery via UPower (events, no polling). Click toggles the percentage; it shows by
// itself at 20% and below while discharging.
Glyph {
    readonly property var dev: UPower.displayDevice
    readonly property real pct: (dev?.percentage ?? 0) * 100
    readonly property bool charging: dev != null &&
        (dev.state === UPowerDeviceState.Charging || dev.state === UPowerDeviceState.FullyCharged)
    readonly property var icons: ["󰁺","󰁻","󰁼","󰁽","󰁾","󰁿","󰂀","󰂁","󰂂","󰁹"]
    readonly property var cicons: ["󰢜","󰂆","󰂇","󰂈","󰢝","󰂉","󰢞","󰂊","󰂋","󰂅"]
    readonly property int idx: Math.max(0, Math.min(9, Math.floor(pct / 10)))
    property bool showPct: false
    visible: dev?.isLaptopBattery ?? false
    text: (charging ? cicons[idx] : icons[idx])
        + (showPct || (pct <= 20 && !charging) ? " " + Math.round(pct) + "%" : "")
    color: pct <= 20 && !charging ? Theme.warn : Theme.fg
    MouseArea { anchors.fill: parent; onClicked: parent.showPct = !parent.showPct }
}
