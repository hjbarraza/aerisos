pragma Singleton
import QtQuick
import Quickshell

// Shell-wide state and helpers. The IPC handlers in shell.qml write here; widgets bind.
Singleton {
    property bool barShown: true
    property int refreshTick: 0   // bumped by `aeris-shell bar refresh`; StatusModules re-run

    function sh(c) { Quickshell.execDetached(["sh", "-c", c]) }

    function isoWeek(d) {
        const t = new Date(d.getTime())
        t.setHours(0, 0, 0, 0)
        t.setDate(t.getDate() + 3 - ((t.getDay() + 6) % 7))
        const w1 = new Date(t.getFullYear(), 0, 4)
        return 1 + Math.round(((t - w1) / 86400000 - 3 + ((w1.getDay() + 6) % 7)) / 7)
    }
}
