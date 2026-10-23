// AerisOS orbit popup — quickshell 0.3.x. Opened by clicking the alerts/airspace pill in the bar.
// Flat world map with day/night, ISS + Tiangong ground tracks, bright satellites overhead Valencia,
// and the alert readouts. Esc, Enter or a click outside closes it. Run via ~/.local/bin/aeris-orbit.
// Data: status.json (collector), /tmp/aeris-screensaver-tracks.json (compute-tracks.py, shared with the saver).
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "land.js" as Land

ShellRoot {
    id: root
    readonly property color bg:   "#000000"
    readonly property color fg:   "#e6e6e6"
    readonly property color dim:  "#7a7a7a"
    readonly property color warn: "#ffffff"
    readonly property color grid: "#2a2a2a"
    readonly property string sans: "Söhne"
    readonly property real obsLat: 39.47    // Valencia
    readonly property real obsLon: -0.38

    property int tick: 0
    property var status: ({})
    property var orbit: ({ tracks: {}, sats: [] })
    function nowS() { return Date.now() / 1000 }
    Timer { interval: 2000; running: true; repeat: true; onTriggered: root.tick++ }

    component JsonFile: FileView {
        id: jf
        property var json: ({})
        signal parsed()
        watchChanges: true
        onFileChanged: this.reload()
        onLoaded: parse()
        function parse() {
            try { jf.json = JSON.parse(this.text()); jf.parsed() } catch (e) {}   // keep the last good data
        }
        Component.onCompleted: parse()
    }
    JsonFile { path: "/var/lib/aeris/status.json"; onParsed: root.status = json }
    JsonFile { path: "/tmp/aeris-screensaver-tracks.json"; onParsed: root.orbit = json }
    property var launches: []
    JsonFile { path: "/tmp/aeris-orbit-launches.json"; onParsed: root.launches = json.launches ?? [] }

    function short(p) {
        return String(p ?? "").replace("China Aerospace Science and Technology Corporation", "CASC")
            .replace("United Launch Alliance", "ULA").replace(" Corporation", "").replace(" Technologies", "").toUpperCase()
    }
    function countdown(l) {   // T-hh:mm:ss, T+ once past the net time
        root.tick
        const d = (Date.parse(l.net) - Date.now()) / 1000, a = Math.abs(d)
        const dd = Math.floor(a / 86400), h = Math.floor(a % 86400 / 3600), m = Math.floor(a % 3600 / 60), sec = Math.floor(a % 60)
        const p = n => String(n).padStart(2, "0")
        return (d < 0 ? "T+" : "T-") + (dd > 0 ? dd + "D " : "") + p(h) + ":" + p(m) + (dd > 0 ? "" : ":" + p(sec))
    }

    function lerpLon(l0, l1, f) {
        const r = l0 + (((l1 - l0 + 540) % 360) - 180) * f
        return r > 180 ? r - 360 : r < -180 ? r + 360 : r
    }
    function trackAt(pts, t) {
        if (!pts || pts.length < 2 || t < pts[0][0] || t > pts[pts.length - 1][0]) return null
        const step = pts[1][0] - pts[0][0]
        const i = Math.min(pts.length - 2, Math.floor((t - pts[0][0]) / step))
        const a = pts[i], b = pts[i + 1]
        const f = (t - a[0]) / (b[0] - a[0])
        return { lat: a[1] + (b[1] - a[1]) * f, lon: lerpLon(a[2], b[2], f) }
    }
    function satAt(s, t) {
        const f = Math.min(1.5, Math.max(0, (t - (orbit.ts ?? t)) / 60))
        return { lat: s.lat + (s.lat1 - s.lat) * f, lon: lerpLon(s.lon, s.lon1, f) }
    }
    // sun position: subsolar latitude/longitude (degrees) for the night shading
    function subsolar(ms) {
        const d = ms / 86400000 - 10957.5, rad = Math.PI / 180
        const L = 280.460 + 0.9856474 * d, g = (357.528 + 0.9856003 * d) * rad
        const lam = (L + 1.915 * Math.sin(g) + 0.020 * Math.sin(2 * g)) * rad
        const eps = (23.439 - 0.0000004 * d) * rad
        const dec = Math.asin(Math.sin(eps) * Math.sin(lam))
        const ra = Math.atan2(Math.cos(eps) * Math.sin(lam), Math.cos(lam)) / rad
        const gmst = 280.46061837 + 360.98564736629 * d
        return { lat: dec / rad, lon: (((ra - gmst) % 360) + 540) % 360 - 180 }
    }


    component Label: Text {
        property real u: 1
        color: root.dim
        font { family: root.sans; pixelSize: 12 * u; letterSpacing: 1 }
    }


    component GroundTrack: Item {
        id: gt
        readonly property real u: Math.max(1, Math.min(1.5, height / 900))
        property bool compact: false      // small flat map for the side column: no corner text
        readonly property real mapW: compact ? width : Math.min(width - 96, 2 * (height - 130))
        readonly property real mapH: mapW / 2
        readonly property real mx: (width - mapW) / 2
        readonly property real my: compact ? 0 : (height - mapH) / 2
        function px(lon) { return mx + (lon + 180) / 360 * mapW }
        function py(lat) { return my + (90 - lat) / 180 * mapH }

        Canvas {   // base map: graticule + coastlines, painted once per size
            x: gt.mx; y: gt.my; width: gt.mapW; height: gt.mapH
            onWidthChanged: requestPaint()
            onPaint: {
                const ctx = getContext("2d")
                ctx.reset()
                ctx.fillStyle = "#070707"; ctx.fillRect(0, 0, width, height)
                ctx.lineWidth = 1; ctx.strokeStyle = "#1a1a1a"
                ctx.beginPath()
                for (let lon = -150; lon <= 150; lon += 30) { const x = Math.round((lon + 180) / 360 * width) + 0.5; ctx.moveTo(x, 0); ctx.lineTo(x, height) }
                for (let lat = -60; lat <= 60; lat += 30) { const y = Math.round((90 - lat) / 180 * height) + 0.5; ctx.moveTo(0, y); ctx.lineTo(width, y) }
                ctx.stroke()
                ctx.fillStyle = "#121212"; ctx.strokeStyle = "#6a6a6a"
                for (const ring of Land.rings) {
                    ctx.beginPath()
                    for (let i = 0; i < ring.length; i++) {
                        const x = (ring[i][0] + 180) / 360 * width, y = (90 - ring[i][1]) / 180 * height
                        if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y)
                    }
                    ctx.closePath(); ctx.fill(); ctx.stroke()
                }
                ctx.strokeStyle = root.grid
                ctx.strokeRect(0.5, 0.5, width - 1, height - 1)
            }
        }

        Canvas {   // night side: black veil whose strength follows the sun's depression below the horizon
            id: night
            x: gt.mx; y: gt.my; width: gt.mapW; height: gt.mapH
            onWidthChanged: requestPaint()
            Timer { interval: 60000; running: gt.visible; repeat: true; triggeredOnStart: true; onTriggered: night.requestPaint() }
            onPaint: {
                const ctx = getContext("2d")
                ctx.reset()
                const s = root.subsolar(Date.now()), rad = Math.PI / 180
                const sd = Math.sin(s.lat * rad), cd = Math.cos(s.lat * rad)
                for (let x = 0; x < width; x += 4) {
                    const lon = (x + 2) / width * 360 - 180
                    const ch = Math.cos((lon - s.lon) * rad)
                    const g = ctx.createLinearGradient(0, 0, 0, height)
                    for (let lat = 90; lat >= -90; lat -= 5) {
                        const alt = Math.asin(Math.sin(lat * rad) * sd + Math.cos(lat * rad) * cd * ch) / rad
                        const t = Math.min(1, Math.max(0, -alt / 18))
                        g.addColorStop((90 - lat) / 180, "rgba(0,0,0," + (0.72 * t).toFixed(3) + ")")
                    }
                    ctx.fillStyle = g
                    ctx.fillRect(x, 0, 4, height)
                }
            }
        }

        Canvas {   // ground tracks: past dim, future bright
            id: lines
            anchors.fill: parent
            property var orbit: root.orbit
            onOrbitChanged: requestPaint()
            onWidthChanged: requestPaint()
            Timer { interval: 30000; running: gt.visible; repeat: true; onTriggered: lines.requestPaint() }
            onPaint: {
                const ctx = getContext("2d")
                ctx.reset()
                const now = root.nowS()
                const names = Object.keys(orbit.tracks ?? {})
                for (const k of names) {
                    const pts = orbit.tracks[k]
                    for (const future of [false, true]) {
                        ctx.beginPath()
                        ctx.lineWidth = future ? 1.5 : 1
                        ctx.strokeStyle = future ? "#e6e6e6" : "#555555"
                        if (k === "CSS") ctx.setLineDash(future ? [6, 4] : [2, 4]); else ctx.setLineDash([])
                        let prev = null
                        for (const p of pts) {
                            if (future ? p[0] < now : p[0] > now) continue
                            const x = gt.px(p[2]), y = gt.py(p[1])
                            if (prev === null || Math.abs(p[2] - prev) > 180) ctx.moveTo(x, y); else ctx.lineTo(x, y)   // break at the antimeridian
                            prev = p[2]
                        }
                        ctx.stroke()
                    }
                }
            }
        }

        // launch pads, numbered as in the list
        Repeater {
            model: root.launches
            Item {
                required property var modelData
                required property int index
                visible: modelData.lat !== null
                x: gt.px(modelData.lon); y: gt.py(modelData.lat)
                Rectangle { x: -4; y: -4; width: 8; height: 8; rotation: 45; color: "#000000"; border { width: 1.5; color: index === 0 ? root.warn : root.fg } }
                Label { u: gt.u * 0.9; x: 8; y: -height / 2; text: String(index + 1); color: root.fg }
            }
        }

        // Valencia
        Rectangle { x: gt.px(root.obsLon) - 2.5; y: gt.py(root.obsLat) - 2.5; width: 5; height: 5; radius: 2.5; color: root.warn }
        Label { u: gt.u * 0.85; x: gt.px(root.obsLon) + 7; y: gt.py(root.obsLat) - height / 2; text: "VALENCIA" }

        // bright satellites above Valencia's horizon
        Repeater {
            model: root.orbit.sats ?? []
            Item {
                required property var modelData
                readonly property var p: { root.tick; return root.satAt(modelData, root.nowS()) }
                x: gt.px(p.lon); y: gt.py(p.lat)
                Rectangle { x: -2; y: -2; width: 4; height: 4; radius: 2; color: root.fg }
                Label { u: gt.u * 0.8; x: 6; y: -height / 2; text: modelData.name }
            }
        }

        // stations, moving along their tracks
        Repeater {
            model: Object.keys(root.orbit.tracks ?? {})
            Item {
                id: st
                required property string modelData
                readonly property var p: { root.tick; return root.trackAt(root.orbit.tracks[modelData], root.nowS()) }
                visible: p !== null
                x: p ? gt.px(p.lon) : 0
                y: p ? gt.py(p.lat) : 0
                Rectangle {
                    x: -width / 2; y: -width / 2; width: 11 * gt.u; height: width
                    radius: st.modelData === "ISS" ? width / 2 : 0
                    color: "#000000"; border.color: root.warn; border.width: 2
                }
                Label { u: gt.u * 1.1; x: 12 * gt.u; y: -height / 2; text: st.modelData === "ISS" ? "ISS" : "TIANGONG"; color: root.warn }
            }
        }

        // corners
        Column {
            visible: !gt.compact
            x: 32; y: 24
            spacing: 4
            Label { u: gt.u; text: "GROUND TRACK"; color: root.fg }
            Label { u: gt.u; text: "ISS ── · TIANGONG ─ ─ · PAST 45 MIN DIM, NEXT 90 MIN BRIGHT" }
        }
        Column {
            visible: !gt.compact
            anchors { right: parent.right; top: parent.top; topMargin: 24; rightMargin: 30 }
            spacing: 4
            Label { u: gt.u; anchors.right: parent.right; text: "NEXT LAUNCH · " + (root.status.space?.launch ?? "—"); color: root.fg }
            Label { u: gt.u; anchors.right: parent.right; text: "T-0 " + (root.status.space?.launch_t0 ?? "—") }
        }
        Column {
            visible: !gt.compact
            anchors { left: parent.left; bottom: parent.bottom; leftMargin: 32; bottomMargin: 20 }
            spacing: 4
            Label { u: gt.u; text: "ISS " + (root.status.space?.iss ?? "—") + "    TIANGONG " + (root.status.space?.css ?? "—"); color: root.fg }
            Label { u: gt.u; text: "OVERHEAD " + (root.status.space?.sats ?? "—") }
        }
    }


    PanelWindow {
        id: win
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: "#cc000000"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "aeris-orbit"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

        Item { anchors.fill: parent; focus: true; Keys.onPressed: Qt.quit() }
        MouseArea { anchors.fill: parent; onClicked: Qt.quit() }

        Rectangle {
            id: card
            anchors.centerIn: parent
            readonly property real sideW: 470
            readonly property real mapW: Math.min(win.width - 100 - sideW - 72, 1500, (win.height - 160) * 2)
            width: mapW + sideW + 72; height: mapW / 2 + 130
            color: root.bg; border { width: 1; color: "#3a3a3a" }
            MouseArea { anchors.fill: parent }   // clicks inside do not close

            Text {
                x: 24; y: 18
                text: "ORBIT  ·  SATELLITES & LAUNCHES"
                color: root.fg
                font { family: root.sans; pixelSize: 15; letterSpacing: 2 }
            }
            Label {
                anchors { right: parent.right; rightMargin: 24; top: parent.top; topMargin: 20 }
                text: "COLLECTED " + (root.status.updated ?? "—") + "  ·  ESC TO CLOSE"
            }

            GroundTrack { x: 24; y: 52; width: card.mapW; height: card.mapW / 2; compact: true }

            Label {
                x: 24; y: 52 + card.mapW / 2 + 8
                text: "ISS ──  ·  TIANGONG ─ ─  ·  ● OVERHEAD VALENCIA NOW  ·  ◇ LAUNCH PADS (NUMBERED)  ·  NIGHT SIDE SHADED"
            }
            Row {   // stations and sky, under the map
                x: 24; y: 52 + card.mapW / 2 + 34
                spacing: 48
                Label { text: "ISS  " + (root.status.space?.iss ?? "—"); color: root.fg; u: 1.15 }
                Label { text: "TIANGONG  " + (root.status.space?.css ?? "—"); color: root.fg; u: 1.15 }
                Label { text: "GNSS  " + (root.status.air?.gnss ?? "—"); color: root.fg; u: 1.15 }
                Label { text: "KP  " + (root.status.space?.kp ?? "—") + "  " + (root.status.space?.scales ?? ""); color: root.fg; u: 1.15 }
            }

            // right column: launches, then what is overhead
            Column {
                x: 24 + card.mapW + 24; y: 52
                width: card.sideW
                spacing: 6
                Label { text: "NEXT LAUNCHES"; color: root.fg }
                Item { width: 1; height: 2 }
                Repeater {
                    model: root.launches
                    Item {
                        id: row
                        required property var modelData
                        required property int index
                        readonly property bool soon: Math.abs(Date.parse(modelData.net) - Date.now()) < 3600000 && modelData.status === "Go"
                        width: card.sideW; height: 52
                        Text {
                            x: 0; y: 0; width: 22
                            text: String(row.index + 1); color: root.dim
                            font { family: root.sans; pixelSize: 13; letterSpacing: 1 }
                        }
                        Rectangle {
                            x: 24; y: -1; width: cd.implicitWidth + 12; height: 18; color: row.soon ? root.warn : "transparent"
                            Text {
                                id: cd
                                anchors.centerIn: parent
                                text: root.countdown(row.modelData)
                                color: row.soon ? "#000000" : root.fg
                                font { family: root.sans; pixelSize: 13; letterSpacing: 1 }
                            }
                        }
                        Label { x: 24 + cd.implicitWidth + 22; y: 1; text: String(row.modelData.status ?? "").toUpperCase() }
                        Text {
                            x: 24; y: 19; width: card.sideW - 24; elide: Text.ElideRight
                            text: (root.short(row.modelData.provider) + " · " + String(row.modelData.vehicle).toUpperCase()).replace("FALCON 9 BLOCK 5", "FALCON 9")
                            color: root.fg
                            font { family: root.sans; pixelSize: 12; letterSpacing: 1 }
                        }
                        Label { x: 24; y: 34; width: card.sideW - 24; elide: Text.ElideRight
                            text: String(row.modelData.mission).toUpperCase() + " · " + String(row.modelData.loc ?? "").split(",")[0].toUpperCase() }
                    }
                }
                Item { width: 1; height: 8 }
                Label { text: "OVERHEAD VALENCIA NOW  (≥10°)"; color: root.fg }
                Item { width: 1; height: 2 }
                Repeater {
                    model: root.orbit.sats ?? []
                    Row {
                        required property var modelData
                        spacing: 10
                        Label { width: 38; text: modelData.el + "°"; color: root.fg }
                        Label { width: card.sideW - 50; elide: Text.ElideRight; text: String(modelData.name).toUpperCase() }
                    }
                }
                Label { visible: (root.orbit.sats ?? []).length === 0; text: "NO BRIGHT SATELLITES ABOVE THE HORIZON" }
            }
        }
    }
}
