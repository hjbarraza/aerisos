pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// /var/lib/aeris/status.json as the shell sees it: re-read when the collector writes it
// (inotify), never polled. Holds the values the bar derives from it. Renderers read;
// nothing in the shell fetches.
Singleton {
    id: status

    property var d: ({})
    property int tick: 0   // staleness is re-evaluated once a minute (no process involved)

    Timer { interval: 60000; running: true; repeat: true; onTriggered: status.tick++ }

    FileView {
        path: "/var/lib/aeris/status.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: status.parse(text())
        onLoadFailed: status.d = ({})
    }

    function parse(text) {
        try { d = JSON.parse(text) } catch (e) { d = ({}) }
    }

    // Airspace events (jamming, squawk, ISS/CSS overhead) have their own pill; these alerts
    // stay out of the general one
    readonly property var airAlerts: ["air.gnss", "air.emergency", "space.iss", "space.css"]
    readonly property var airHot: {
        const out = []
        for (const a of d.alerts || []) {
            if (a === "air.gnss") out.push("GNSS " + String(d.air?.gnss ?? "JAMMED").split(" ")[0])
            else if (a === "air.emergency") out.push("SQUAWK " + String(d.air?.emergency ?? "").split(" ")[0])
            else if (a === "space.iss") out.push("ISS OVERHEAD")
            else if (a === "space.css") out.push("CSS OVERHEAD")
        }
        return out
    }
    // Bright satellites above 10 degrees right now ("5 O/H · ARIANE 40 R/B")
    readonly property int airSats: parseInt(/^\s*(\d+)\s*O\/H/.exec(String(d.space?.sats ?? ""))?.[1] ?? "0")
    readonly property var airLabels: airHot.concat(airSats > 0 ? [airSats + " SAT" + (airSats === 1 ? "" : "S") + " O/H"] : [])

    // One short label per remaining status.json alert, shown inverted in the bar
    readonly property var labels: {
        const out = []
        for (const a of d.alerts || []) {
            if (airAlerts.includes(a)) continue
            else if (a === "space.scales") out.push((/G\d/.exec(String(d.space?.scales ?? ""))?.[0] ?? "G?") + " STORM")
            else if (a === "world.outages") out.push("NET OUTAGE " + (String(d.net?.city ?? "").split(", ").pop() ?? ""))
            else out.push(a.toUpperCase())
        }
        return out
    }

    readonly property int watchNew:
        (d.watch?.items ?? []).reduce((n, i) => n + (i.new?.length ?? 0), 0)

    // The collector writes every minute; much older than 10 min means it is down
    readonly property bool stale: {
        tick
        const m = /^(\d\d):(\d\d)$/.exec(d.updated ?? "")
        if (!m) return true
        const now = new Date()
        return ((now.getHours() * 60 + now.getMinutes()
                 - parseInt(m[1]) * 60 - parseInt(m[2])) + 1440) % 1440 > 10
    }
}
