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
    property var orbit: ({ tracks: {}, sats: [], info: {} })
    property string selected: ""     // sat or station name, from a map dot or a sidebar row
    property int selLaunch: -1       // index into launches; clears `selected` and vice versa
    // full-catalog mode: dot cloud + hover + click-to-select (n exclusive selection slots)
    property bool catalog: false
    property int catalogSel: -1      // NORAD id of a selected catalog object
    property var catalogData: ({})
    property var selData: ({})       // daemon's answer for catalogSel (req-keyed)
    property int hoverIdx: -1
    readonly property var hoverObj: root.currentObjects()[hoverIdx] ?? []
    // cuts: view transform + region + group + bands + search
    property real zoom: 1            // 1 = whole world
    property real cLon: 0
    property real cLat: 0
    property var region: null        // {lon0, lat0, lon1, lat1} in data coords
    property var groups: ({})        // /tmp/aeris-orbit-groups.json
    property string groupSel: ""     // selected group chip
    property var bands: []           // selected orbit-family indexes
    property string search: ""       // committed search text (uppercased)
    readonly property bool rowsAlt: search.length > 0 || region !== null
    property var rowItems: []        // search/region rows shown in the right column
    function currentObjects() {
        if (groupSel) return (groups.groups?.[groupSel]) ?? []
        if (catalog) return catalogData.objects ?? []
        return []
    }
    function inBox(lat, lon) {
        const r = region
        if (!r) return true
        const mid = (r.lon0 + r.lon1) / 2
        const wrap = d => (((d - mid + 540) % 360) - 180)
        return wrap(lon) >= wrap(Math.min(r.lon0, r.lon1)) && wrap(lon) <= wrap(Math.max(r.lon0, r.lon1)) &&
               lat >= Math.min(r.lat0, r.lat1) && lat <= Math.max(r.lat0, r.lat1)
    }
    function passFilters(o) {   // o = [norad, name, lat, lon, lat1, lon1, band]
        if (bands.length && bands.indexOf(o[6]) < 0) return false
        return inBox(o[2], o[3])
    }
    function clampC() {
        cLat = Math.max(-(90 - 90 / Math.max(1, zoom)), Math.min(90 - 90 / Math.max(1, zoom), cLat))
    }
    function rebuildRows() {    // search/region rows for the right column
        const src = search.length ? currentObjects().filter(o => String(o[1]).toUpperCase().includes(search.toUpperCase()))
                                  : (region ? currentObjects() : [])
        let rows = []
        for (const o of src) if (passFilters(o)) { rows.push({ "norad": o[0], "name": o[1] }); if (rows.length >= 150) break }
        return rows
    }
    function nowS() { return Date.now() / 1000 }
    Timer { interval: 2000; running: true; repeat: true; onTriggered: root.tick++ }

    component Chip: Rectangle {   // filter pill: label + on state + click signal
        property string text: "?"
        property bool on: false
        signal pick()
        width: chipText.implicitWidth + 14; height: 17; radius: 3
        color: on ? root.warn : "transparent"
        border { width: 1; color: root.fg }
        Text { id: chipText; anchors.centerIn: parent; text: parent.text
               color: parent.on ? "#000000" : root.fg
               font { family: root.sans; pixelSize: 11; letterSpacing: 1 } }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: parent.pick() }
    }
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
    JsonFile { id: catJf; path: "/tmp/aeris-orbit-catalog.json"; watchChanges: root.catalog
                onParsed: root.catalogData = catJf.json }
    JsonFile { id: grpJf; path: "/tmp/aeris-orbit-groups.json"
                onParsed: root.groups = grpJf.json }
    JsonFile { id: selJf; path: "/tmp/aeris-orbit-selected.json"
                onParsed: if (selJf.json.norad === root.catalogSel) root.selData = selJf.json }

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
    function infoOf(name) { return root.orbit.info?.[name] ?? {} }
    function displayName(n) { return n === "CSS" ? "TIANGONG" : n }
    function launchOf(i) { return root.launches[i] ?? {} }
    function utcHM(iso) { return String(iso ?? "").slice(11, 16) }
    function localDT(iso) { return Qt.formatDateTime(new Date(Date.parse(iso ?? "")), "ddd d MMM HH:mm") }
    function clearCatalog() { root.catalogSel = -1; root.selData = ({}); root.hoverIdx = -1 }
    function wantCatalog(norad) {   // ask the daemon for one object's info + track; req keyed
        if (norad === undefined) return
        Quickshell.execDetached(["sh", "-c",
            "printf '{\"req\":" + Date.now() + ",\"norad\":" + norad + "}' > /tmp/aeris-orbit-want.json"])
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
        function px(lon) { return mx + (0.5 + (((lon - root.cLon + 540) % 360) - 180) * root.zoom / 360) * mapW }
        function py(lat) { return my + (0.5 - (lat - root.cLat) * root.zoom / 180) * mapH }
        function lonAt(x) { return root.cLon + ((x - mx) / mapW - 0.5) * 360 / root.zoom }
        function latAt(y) { return root.cLat + (0.5 - (y - my) / mapH) * 180 / root.zoom }
        readonly property var view: ({ z: root.zoom, lon: root.cLon, lat: root.cLat })

        Canvas {   // base map: graticule + coastlines, painted once per size / view change
            id: baseMap
            x: gt.mx; y: gt.my; width: gt.mapW; height: gt.mapH
            property var view: gt.view
            onViewChanged: requestPaint()
            onWidthChanged: requestPaint()
            onPaint: {
                const ctx = getContext("2d")
                ctx.reset()
                ctx.fillStyle = "#070707"; ctx.fillRect(0, 0, width, height)
                ctx.lineWidth = 1; ctx.strokeStyle = "#1a1a1a"
                ctx.beginPath()
                for (let lon = Math.floor(gt.lonAt(0) / 30) * 30; lon <= gt.lonAt(width); lon += 30) {
                    const x = Math.round(gt.px(lon)) + 0.5
                    if (x < -1 || x > width + 1) continue
                    ctx.moveTo(x, 0); ctx.lineTo(x, height)
                }
                for (let lat = Math.ceil(gt.latAt(height) / 30) * 30; lat <= gt.latAt(0); lat += 30) {
                    const y = Math.round(gt.py(lat)) + 0.5
                    if (y < -1 || y > height + 1) continue
                    ctx.moveTo(0, y); ctx.lineTo(width, y)
                }
                ctx.stroke()
                ctx.fillStyle = "#121212"; ctx.strokeStyle = "#6a6a6a"
                for (const ring of Land.rings) {
                    ctx.beginPath()
                    let on = false, off = false
                    for (let i = 0; i < ring.length; i++) {
                        const x = gt.px(ring[i][0]), y = gt.py(ring[i][1])
                        if (x < -16 || x > width + 16 || y < -16 || y > height + 16) { on = false; continue }
                        off = true
                        if (!on) { ctx.moveTo(x, y); on = true } else ctx.lineTo(x, y)
                    }
                    if (off) { ctx.closePath(); ctx.fill(); ctx.stroke() }
                }
                ctx.strokeStyle = root.grid
                ctx.strokeRect(0.5, 0.5, width - 1, height - 1)
            }
        }

        Canvas {   // night side: black veil whose strength follows the sun's depression below the horizon
            id: night
            x: gt.mx; y: gt.my; width: gt.mapW; height: gt.mapH
            property var view: gt.view
            onViewChanged: requestPaint()
            onWidthChanged: requestPaint()
            Timer { interval: 60000; running: gt.visible; repeat: true; triggeredOnStart: true; onTriggered: night.requestPaint() }
            onPaint: {
                const ctx = getContext("2d")
                ctx.reset()
                const s = root.subsolar(Date.now()), rad = Math.PI / 180
                const sd = Math.sin(s.lat * rad), cd = Math.cos(s.lat * rad)
                for (let x = 0; x < width; x += 4) {
                    const lon = gt.lonAt(x + 2)
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
            property var sel: root.selData          // repaint on catalog selection changes too
            property int csel: root.catalogSel
            property var view: gt.view
            onViewChanged: requestPaint()
            onSelChanged: requestPaint()
            onCselChanged: requestPaint()
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
                        ctx.setLineDash([])
                    }
                }
                const sp = root.selData   // selected catalog object's own track, in warn white
                if (root.catalogSel >= 0 && (root.catalog || root.groupSel !== "") && (sp.norad ?? 0) === root.catalogSel && (sp.track ?? []).length > 1) {
                    for (const future of [false, true]) {
                        ctx.beginPath()
                        ctx.lineWidth = future ? 1.5 : 1
                        ctx.strokeStyle = future ? "#ffffff" : "#5f5f5f"
                        let prev = null
                        for (const p of sp.track) {
                            if (future ? p[0] < now : p[0] > now) continue
                            const x = gt.px(p[2]), y = gt.py(p[1])
                            if (prev === null || Math.abs(p[2] - prev) > 180) ctx.moveTo(x, y); else ctx.lineTo(x, y)
                            prev = p[2]
                        }
                        ctx.stroke()
                    }
                }
            }
        }

        Canvas {   // dot cloud of the active source, filtered by region + bands
            id: dotsC
            anchors.fill: parent
            visible: root.catalog || root.groupSel
            property var data: root.catalogData
            property var grp: root.groups
            property var view: gt.view
            onDataChanged: requestPaint()
            onGrpChanged: requestPaint()
            onViewChanged: requestPaint()
            onWidthChanged: requestPaint()
            onPaint: {
                const ctx = getContext("2d")
                ctx.reset()
                const objs = root.currentObjects()
                if (!objs.length) return
                const now = root.nowS(), ts = Math.max(root.catalogData.ts ?? 0, root.groups.ts ?? 0)
                const f = (now - ts) / 60
                const t0 = Date.now()
                ctx.fillStyle = "#5f5f5f"
                for (let i = 0; i < objs.length; i++) {
                    const o = objs[i]
                    if (!root.passFilters(o)) continue
                    ctx.fillRect(gt.px(root.lerpLon(o[3], o[5], f)) - 0.75, gt.py(o[2] + (o[4] - o[2]) * f) - 0.75, 1.5, 1.5)
                }
                const ms = Date.now() - t0
                if (ms > 8) console.log("catalog paint:", ms, "ms")
            }
            Timer { interval: 10000; running: root.catalog || root.groupSel !== ""; repeat: true; onTriggered: dotsC.requestPaint() }
        }

        MouseArea {   // hover + click + zoom + pan + rubber-band region; under the dots' own handlers
            id: mapMouse
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: (root.catalog || root.groupSel !== "") && root.hoverIdx >= 0
                         ? Qt.PointingHandCursor : Qt.ArrowCursor
            property real lastCheck: 0
            readonly property real half: 81
            property bool panning: false
            property var pan0: null
            property bool dragging: false
            property var drag0: null
            property var drag1: null
            function nearest(px, py) {     // nearest visible dot within 9 px
                const objs = root.currentObjects()
                if (!objs.length) return -1
                const now = root.nowS(), ts = Math.max(root.catalogData.ts ?? 0, root.groups.ts ?? 0)
                const f = (now - ts) / 60
                let best = -1, bd = mapMouse.half
                for (let i = 0; i < objs.length; i++) {
                    const o = objs[i]
                    if (!root.passFilters(o)) continue
                    const dx = gt.px(root.lerpLon(o[3], o[5], f)) - px
                    const dy = gt.py(o[2] + (o[4] - o[2]) * f) - py
                    const d = dx * dx + dy * dy
                    if (d < bd) { bd = d; best = i }
                }
                return best
            }
            function zoomAt(x, y, fac) {   // cursor-anchored: the point under the cursor stays put
                const lo = gt.lonAt(x), la = gt.latAt(y)
                const z2 = Math.min(24, Math.max(1, root.zoom * fac))
                if (z2 === root.zoom) return
                if (z2 <= 1) { root.zoom = 1; root.cLon = 0; root.cLat = 0; return }
                root.zoom = z2
                root.cLon = lo - ((x - gt.mx) / gt.mapW - 0.5) * 360 / z2
                root.cLat = la - (0.5 - (y - gt.my) / gt.mapH) * 180 / z2
                root.clampC()
            }
            onWheel: w => mapMouse.zoomAt(w.x, w.y, w.angleDelta.y > 0 ? 1.25 : 0.8)
            onPressed: mouse => {
                if (mouse.button === Qt.RightButton) { panning = true; pan0 = Qt.point(mouse.x, mouse.y); return }
                if (mapMouse.nearest(mouse.x, mouse.y) < 0) {
                    dragging = true; drag0 = Qt.point(mouse.x, mouse.y); drag1 = drag0
                }
            }
            onPositionChanged: mouse => {
                if (panning) {
                    root.cLon -= (mouse.x - pan0.x) * 360 / root.zoom / gt.mapW
                    root.cLat += (mouse.y - pan0.y) * 180 / root.zoom / gt.mapH
                    pan0 = Qt.point(mouse.x, mouse.y)
                    root.clampC()
                    return
                }
                if (dragging) { drag1 = Qt.point(mouse.x, mouse.y); return }
                if (!(mouse.buttons & Qt.LeftButton) && (root.catalog || root.groupSel !== "")) {
                    const n = Date.now()
                    if (n - mapMouse.lastCheck < 40) return   // throttle the 16k-dot scans
                    mapMouse.lastCheck = n
                    root.hoverIdx = mapMouse.nearest(mouse.x, mouse.y)
                }
            }
            onReleased: mouse => {
                if (mouse.button === Qt.RightButton) { panning = false; return }
                if (dragging) {
                    dragging = false
                    const dx = mouse.x - drag0.x, dy = mouse.y - drag0.y
                    const x0 = drag0.x, y0 = drag0.y
                    drag0 = null; drag1 = null
                    if (dx * dx + dy * dy < 49) {              // too small: an empty-map click
                        root.selected = ""; root.selLaunch = -1
                        root.clearCatalog()
                        return
                    }
                    root.region = { "lon0": gt.lonAt(Math.min(x0, mouse.x)), "lat0": gt.latAt(Math.min(y0, mouse.y)),
                                    "lon1": gt.lonAt(Math.max(x0, mouse.x)), "lat1": gt.latAt(Math.max(y0, mouse.y)) }
                    root.rowItems = root.rebuildRows()
                    return
                }
                const i = mapMouse.nearest(mouse.x, mouse.y)   // plain click
                root.selected = ""; root.selLaunch = -1
                if (i >= 0) {
                    root.selData = ({}); root.catalogSel = root.currentObjects()[i][0]
                    root.wantCatalog(root.currentObjects()[i][0])
                } else root.clearCatalog()
            }
            onExited: root.hoverIdx = -1
        }

        // launch pads, numbered as in the list
        Repeater {
            model: root.launches
            Item {
                required property var modelData
                required property int index
                readonly property bool sel: root.selLaunch === index
                visible: modelData.lat !== null
                x: gt.px(modelData.lon); y: gt.py(modelData.lat)
                Rectangle { x: -4; y: -4; width: 8; height: 8; rotation: 45
                            color: parent.sel ? root.warn : "#000000"
                            border { width: 1.5; color: index === 0 || parent.sel ? root.warn : root.fg } }
                Label { u: gt.u * 0.9; x: 8; y: -height / 2; text: String(index + 1); color: root.fg }
                MouseArea {
                    x: -12; y: -12; width: 28; height: 28
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { root.selected = ""; root.clearCatalog(); root.selLaunch = parent.sel ? -1 : index }
                }
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
                readonly property bool sel: root.selected === modelData.name
                x: gt.px(p.lon); y: gt.py(p.lat); z: sel ? 10 : 0
                Rectangle {   // selection ring, matches the inverted sidebar row
                    visible: parent.sel
                    x: -9; y: -9; width: 18; height: 18; radius: 9
                    color: "transparent"; border { width: 1.5; color: root.warn }
                }
                Rectangle { x: -2.5; y: -2.5; width: parent.sel ? 7 : 5; height: width; radius: width / 2
                            color: parent.sel ? root.warn : root.fg }
                MouseArea {   // generous hit area; click again to deselect
                    x: -15; y: -15; width: 30; height: 30
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { root.selLaunch = -1; root.clearCatalog(); root.selected = parent.sel ? "" : modelData.name }
                }
                Label { u: gt.u * 0.8; x: 6; y: -height / 2; text: modelData.name
                        color: parent.sel ? root.warn : root.dim }
            }
        }

        // stations, moving along their tracks
        Repeater {
            model: Object.keys(root.orbit.tracks ?? {})
            Item {
                id: st
                required property string modelData
                readonly property var p: { root.tick; return root.trackAt(root.orbit.tracks[modelData], root.nowS()) }
                readonly property bool sel: root.selected === modelData
                visible: p !== null
                x: p ? gt.px(p.lon) : 0
                y: p ? gt.py(p.lat) : 0
                Rectangle {
                    x: -width / 2; y: -width / 2; width: 11 * gt.u; height: width
                    radius: st.modelData === "ISS" ? width / 2 : 0
                    color: st.sel ? root.warn : "#000000"
                    border.color: root.warn; border.width: 2
                }
                Label { u: gt.u * 1.1; x: 12 * gt.u; y: -height / 2
                        text: st.modelData === "ISS" ? "ISS" : "TIANGONG"
                        color: st.sel ? root.warn : root.fg }
                MouseArea {
                    x: -14; y: -14; width: 28; height: 28
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { root.selLaunch = -1; root.clearCatalog(); root.selected = st.sel ? "" : st.modelData }
                }
            }
        }

        // hovered catalog dot: ring + name, drifting with it
        Item {
            id: hov
            property var o: root.hoverObj   // follows the hover selection reactively
            readonly property string src: root.groupSel !== "" ? String(root.groups.ts ?? root.nowS())
                                                               : String(root.catalogData.ts ?? root.nowS())
            visible: (root.catalog || root.groupSel !== "") && root.hoverIdx >= 0 && o.length >= 6
            readonly property real f: { root.tick; return (root.nowS() - Number(src)) / 60 }
            x: gt.px(root.lerpLon(o[3], o[5], f)); y: gt.py(o[2] + (o[4] - o[2]) * f)
            Rectangle { x: -8; y: -8; width: 16; height: 16; radius: 8
                        color: "transparent"; border { width: 1.5; color: root.fg } }
            Label { x: 10; y: -height / 2; text: String(hov.o[1] ?? "").toUpperCase(); color: root.fg }
        }

        // rubber band while dragging + committed region box, in data space
        Rectangle {
            readonly property bool live: mapMouse.drag0 !== null && mapMouse.drag1 !== null
            readonly property var r: root.region
            visible: live || (r !== null && (root.groupSel !== "" || root.catalog))
            x: live ? Math.min(mapMouse.drag0.x, mapMouse.drag1.x)
                    : (r ? Math.min(gt.px(r.lon0), gt.px(r.lon1)) : 0)
            y: live ? Math.min(mapMouse.drag0.y, mapMouse.drag1.y)
                    : (r ? Math.min(gt.py(r.lat0), gt.py(r.lat1)) : 0)
            width: live ? Math.abs(mapMouse.drag1.x - mapMouse.drag0.x)
                        : (r ? Math.abs(gt.px(r.lon1) - gt.px(r.lon0)) : 0)
            height: live ? Math.abs(mapMouse.drag1.y - mapMouse.drag0.y)
                         : (r ? Math.abs(gt.py(r.lat1) - gt.py(r.lat0)) : 0)
            color: "transparent"
            border { width: 1.5; color: root.fg }
        }

        // selected catalog object: warn ring on its drifting position (its track draws in `lines`)
        Item {
            id: catMarker
            readonly property bool on: root.catalogSel >= 0 && (root.catalog || root.groupSel !== "")
                                        && root.selData.norad === root.catalogSel
                                        && (root.selData.track ?? []).length > 1
            readonly property var p: { root.tick
                return catMarker.on ? root.trackAt(root.selData.track, root.nowS()) : null }
            visible: p !== null
            x: p ? gt.px(p.lon) : 0; y: p ? gt.py(p.lat) : 0
            Rectangle { x: -width / 2; y: -width / 2; width: 10; height: 10; radius: 5
                        color: "#000000"; border { width: 2; color: root.warn } }
            Label { u: gt.u * 0.9; x: 10; y: -height / 2; text: String(root.selData.name ?? "").split("(")[0].toUpperCase()
                    color: root.warn }
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

        Item {
            anchors.fill: parent; focus: true
            Keys.onPressed: event => {   // Esc unwinds: region → search → group → catalog → selection → close
                if (event.key !== Qt.Key_Escape) return
                event.accepted = true
                if (root.region) { root.region = null; root.rowItems = root.rebuildRows() }
                else if (root.search) { root.search = ""; root.rowItems = [] }
                else if (root.groupSel) { root.groupSel = "" }
                else if (root.catalog) { root.catalog = false }
                else if (root.bands.length) { root.bands = [] }
                else if (root.zoom > 1) { root.zoom = 1; root.cLon = 0; root.cLat = 0 }
                else if (root.catalogSel >= 0) root.clearCatalog()
                else if (root.selected || root.selLaunch >= 0) { root.selected = ""; root.selLaunch = -1 }
                else Qt.quit()
            }
        }
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

            // selected object stamp: fed by a map-dot click or a sidebar row; click again / ✕ to close
            Rectangle {
                id: stamp
                visible: root.selected !== ""
                property var o: root.infoOf(root.selected)
                x: 36; y: 64; width: 252
                height: detailsCol.implicitHeight + 30
                color: "#e8070707"; border { width: 1; color: "#3a3a3a" }
                MouseArea { anchors.fill: parent }   // clicks inside don't hit the backdrop
                Column {
                    id: detailsCol
                    x: 14; y: 11; width: parent.width - 28; spacing: 4
                    Text {
                        width: parent.width; rightPadding: 18
                        text: root.displayName(root.selected).toUpperCase() + "  ·  NORAD " + (stamp.o.norad ?? "—")
                        color: root.warn; font { family: root.sans; pixelSize: 13; letterSpacing: 2 }
                    }
                    Label { width: parent.width; text: "EL  " + (stamp.o.el ?? "—") + "°   AZ  " + (stamp.o.az ?? "—") + "°"; color: root.fg }
                    Label { width: parent.width; text: "ALT " + (stamp.o.alt ?? "—") + " km   " + (stamp.o.vel ?? "—") + " km/s"; color: root.fg }
                    Label { width: parent.width; text: "INCL " + (stamp.o.incl ?? "—") + "°   PERIOD " + (stamp.o.period ?? "—") + " min"; color: root.fg }
                    Label { width: parent.width; text: "APO " + (stamp.o.apo ?? "—") + " · PERIGEE " + (stamp.o.peri ?? "—") + " km"; color: root.fg }
                    Label { width: parent.width; visible: root.selected === "ISS" || root.selected === "CSS"
                            text: "NEXT " + (root.selected === "ISS" ? root.status.space?.iss : root.status.space?.css ?? "—"); color: root.fg }
                }
                Item {  // close corner
                    width: 16; height: 16
                    anchors { right: parent.right; top: parent.top; topMargin: 6; rightMargin: 6 }
                    Text { anchors.centerIn: parent; text: "✕"; color: root.dim; font { family: root.sans; pixelSize: 11 } }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.selected = "" }
                }
            }

            // selected-launch stamp: same corner as the satellite stamp; selecting either clears the other
            Rectangle {
                id: stampL
                visible: root.selLaunch >= 0
                property var l: root.launchOf(root.selLaunch)
                x: 36; y: 64; width: 252
                height: launchCol.implicitHeight + 30
                color: "#e8070707"; border { width: 1; color: "#3a3a3a" }
                MouseArea { anchors.fill: parent }
                Column {
                    id: launchCol
                    x: 14; y: 11; width: parent.width - 28; spacing: 4
                    Text {
                        width: parent.width
                        text: String(root.selLaunch + 1) + " · " + String(stampL.l.mission ?? "—").toUpperCase()
                        elide: Text.ElideRight
                        color: root.warn; font { family: root.sans; pixelSize: 13; letterSpacing: 2 }
                    }
                    Text {
                        width: parent.width
                        text: root.countdown(stampL.l) + "  ·  NET " + root.localDT(stampL.l.net)
                        color: root.fg; font { family: root.sans; pixelSize: 13; letterSpacing: 1 }
                    }
                    Label { width: parent.width; visible: String(stampL.l.ws ?? "") > "" && String(stampL.l.we ?? "") > ""
                            text: "WINDOW " + root.utcHM(stampL.l.ws) + " – " + root.utcHM(stampL.l.we) + " UTC"; color: root.fg }
                    Label { width: parent.width; text: root.short(stampL.l.provider) + "  ·  " + String(stampL.l.vehicle ?? "").toUpperCase().replace("FALCON 9 BLOCK 5", "FALCON 9"); color: root.fg }
                    Label { width: parent.width; text: "STATUS " + String(stampL.l.status ?? "—").toUpperCase() + "  ·  " + String(stampL.l.mtype ?? "").toUpperCase(); color: root.fg }
                    Label { width: parent.width; elide: Text.ElideRight
                            text: "ORBIT " + (stampL.l.orbit ?? "TBD").toUpperCase(); color: root.fg }
                    Label { width: parent.width; elide: Text.ElideRight
                            text: "PAD " + (stampL.l.pad ?? "—") + ", " + (stampL.l.loc ?? "").toUpperCase(); color: root.fg }
                    Text {
                        width: parent.width; visible: String(stampL.l.desc ?? "") > ""
                        text: stampL.l.desc ?? ""
                        elide: Text.ElideRight; wrapMode: Text.WordWrap
                        maximumLineCount: 3; lineHeight: 1.1
                        color: root.dim; font { family: root.sans; pixelSize: 11 }
                    }
                }
                Item {  // close corner
                    width: 16; height: 16
                    anchors { right: parent.right; top: parent.top; topMargin: 6; rightMargin: 6 }
                    Text { anchors.centerIn: parent; text: "✕"; color: root.dim; font { family: root.sans; pixelSize: 11 } }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.selLaunch = -1 }
                }
            }

            // selected catalog object: same fields, from the daemon's on-demand answer
            Rectangle {
                id: stampC
                visible: (root.catalog || root.groupSel !== "") && root.catalogSel >= 0 &&
                         ((root.selData.norad ?? -2) === root.catalogSel || root.selData.error !== undefined)
                x: 36; y: 64; width: 252
                height: catCol.implicitHeight + 30
                color: "#e8070707"; border { width: 1; color: "#3a3a3a" }
                MouseArea { anchors.fill: parent }
                property var o: root.selData.info ?? {}
                Column {
                    id: catCol
                    x: 14; y: 11; width: parent.width - 28; spacing: 4
                    Text {
                        width: parent.width
                        text: root.selData.error ? "NORAD " + root.catalogSel + " · NOT IN CATALOG"
                                                 : String(root.selData.name ?? "…").toUpperCase() + "  ·  NORAD " + root.catalogSel
                        elide: Text.ElideRight
                        color: root.warn; font { family: root.sans; pixelSize: 13; letterSpacing: 2 }
                    }
                    Label { width: parent.width; text: "EL  " + (stampC.o.el ?? "—") + "°   AZ  " + (stampC.o.az ?? "—") + "°"; color: root.fg }
                    Label { width: parent.width; text: "ALT " + (stampC.o.alt ?? "—") + " km   " + (stampC.o.vel ?? "—") + " km/s"; color: root.fg }
                    Label { width: parent.width; text: "INCL " + (stampC.o.incl ?? "—") + "°   PERIOD " + (stampC.o.period ?? "—") + " min"; color: root.fg }
                    Label { width: parent.width; text: "APO " + (stampC.o.apo ?? "—") + " · PERIGEE " + (stampC.o.peri ?? "—") + " km"; color: root.fg }
                }
                Item {  // close corner
                    width: 16; height: 16
                    anchors { right: parent.right; top: parent.top; topMargin: 6; rightMargin: 6 }
                    Text { anchors.centerIn: parent; text: "✕"; color: root.dim; font { family: root.sans; pixelSize: 11 } }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.clearCatalog() }
                }
            }

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
                Row {   // catalog row: source toggle + count + name search
                    Text { text: "CATALOG"; color: root.fg
                           font { family: root.sans; pixelSize: 13; letterSpacing: 1 } }
                    Item { width: 6; height: 1 }
                    Chip { text: "ALL ACTIVE"; on: root.catalog || root.groupSel !== ""
                           onPick: {
                               root.selected = ""; root.selLaunch = -1; root.clearCatalog()
                               root.groupSel = ""
                               root.catalog = !root.catalog
                               if (root.catalog) catJf.reload()
                               root.rowItems = root.rebuildRows()
                           } }
                    Rectangle {   // name search: commit on Enter, Esc clears
                        width: 130; height: 17; radius: 3
                        color: "transparent"; border { width: 1; color: root.fg }
                        TextInput {
                            id: searchT
                            anchors.fill: parent; anchors.leftMargin: 6; anchors.rightMargin: 4
                            verticalAlignment: TextInput.AlignVCenter
                            color: root.fg; clip: true
                            font { family: root.sans; pixelSize: 11; letterSpacing: 1 }
                            Text { anchors.fill: parent; visible: searchT.displayText === ""
                                   text: "SEARCH"; color: root.dim; verticalAlignment: Text.AlignVCenter
                                   font { family: root.sans; pixelSize: 11; letterSpacing: 1 } }
                            onAccepted: { root.search = text.toUpperCase(); root.rowItems = root.rebuildRows() }
                            Keys.onEscapePressed: {
                                text = ""; root.search = ""; root.rowItems = root.rebuildRows(); focus = false
                            }
                        }
                    }
                    Label { visible: root.catalog || root.groupSel !== ""
                            text: (root.currentObjects().length || "…") +
                                  (root.catalog && root.catalogData.tleAge !== undefined
                                   ? " · TLE " + root.catalogData.tleAge + " H" : "")
                            color: root.dim }
                }
                Flow {   // bands + groups + region chips
                    width: card.sideW; spacing: 4
                    Repeater { model: ["LOW", "MID", "MEO", "GEO", "HEO"]
                        Chip { required property var modelData
                               required property int index
                               text: modelData; on: root.bands.indexOf(index) >= 0
                               onPick: {
                                   if (!(root.catalog || root.groupSel !== "")) { root.catalog = true; catJf.reload() }
                                   const i = root.bands.indexOf(index)
                                   if (i >= 0) root.bands.splice(i, 1); else root.bands.push(index)
                                   root.bands = root.bands.slice()
                                   root.rowItems = root.rebuildRows()
                               } } }
                    Text { text: "GROUPS"; height: 17; color: root.dim; verticalAlignment: Text.AlignVCenter
                           font { family: root.sans; pixelSize: 10; letterSpacing: 1 } }
                    Repeater { model: Object.keys(root.groups.groups ?? {})
                        Chip { required property string modelData
                               text: modelData; on: root.groupSel === modelData
                               onPick: {
                                   root.selected = ""; root.selLaunch = -1; root.clearCatalog()
                                   root.groupSel = root.groupSel === modelData ? "" : modelData
                                   if (root.groupSel !== "") root.catalog = false
                                   root.rowItems = root.rebuildRows()
                               } } }
                    Chip { visible: root.region !== null; text: "✕ REGION"
                           onPick: { root.region = null; root.rowItems = root.rebuildRows() } }
                }
                Item { width: 1; height: 2 }
                Label { visible: root.rowItems.length > 0; color: root.fg
                        text: root.search ? "SEARCH '" + root.search + "' — " + root.rowItems.length
                                          : "IN REGION — " + root.rowItems.length }
                Label { visible: root.rowsAlt && root.rowItems.length === 0
                                 && (root.catalog || root.groupSel !== ""); color: root.dim
                        text: "NO MATCHES IN THIS REGION" }
                Repeater {
                    model: root.rowItems
                    Item {   // one result row: name + norad, click = select
                        required property var modelData
                        readonly property bool sel: root.catalogSel === modelData.norad
                        width: card.sideW; height: 15
                        Rectangle { visible: parent.sel; x: -6; y: -2; width: card.sideW - 12; height: 18
                                    color: root.warn; radius: 3 }
                        Label { x: 0; width: card.sideW - 130; elide: Text.ElideRight
                                text: String(modelData.name).toUpperCase()
                                color: parent.sel ? "#000000" : root.fg }
                        Label { x: card.sideW - 110; width: 110; text: "NORAD " + modelData.norad
                                color: parent.sel ? "#000000" : root.dim }
                        MouseArea { x: -6; y: -2; width: card.sideW - 12; height: 18
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.selLaunch = -1; root.selected = ""
                                        root.selData = ({}); root.clearCatalog()
                                        root.catalogSel = parent.sel ? -1 : modelData.norad
                                        if (!parent.sel) root.wantCatalog(modelData.norad)
                                    } }
                    }
                }
                Item { width: 1; height: 4 }
                Label { text: "NEXT LAUNCHES"; color: root.fg }
                Item { width: 1; height: 2 }
                Repeater {
                    model: root.launches
                    Item {
                        id: row
                        required property var modelData
                        required property int index
                        readonly property bool soon: Math.abs(Date.parse(modelData.net) - Date.now()) < 3600000 && modelData.status === "Go"
                        readonly property bool sel: root.selLaunch === index
                        width: card.sideW; height: 52
                        Rectangle { visible: parent.sel; x: -6; y: -3; width: card.sideW - 12; height: 58
                                    color: root.warn; radius: 3 }
                        MouseArea {
                            x: -6; y: -3; width: card.sideW - 12; height: 58
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { root.selected = ""; root.clearCatalog(); root.selLaunch = parent.sel ? -1 : row.index }
                        }
                        Text {
                            x: 0; y: 0; width: 22
                            text: String(row.index + 1); color: row.sel ? "#000000" : root.dim
                            font { family: root.sans; pixelSize: 13; letterSpacing: 1 }
                        }
                        Rectangle {
                            x: 24; y: -1; width: cd.implicitWidth + 12; height: 18
                            color: row.soon ? root.warn : (row.sel ? "#d8d8d8" : "transparent")
                            Text {
                                id: cd
                                anchors.centerIn: parent
                                text: root.countdown(row.modelData)
                                color: row.soon || row.sel ? "#000000" : root.fg
                                font { family: root.sans; pixelSize: 13; letterSpacing: 1 }
                            }
                        }
                        Label { x: 24 + cd.implicitWidth + 22; y: 1; text: String(row.modelData.status ?? "").toUpperCase();
                                color: row.sel ? "#000000" : root.dim }
                        Text {
                            x: 24; y: 19; width: card.sideW - 24; elide: Text.ElideRight
                            text: (root.short(row.modelData.provider) + " · " + String(row.modelData.vehicle).toUpperCase()).replace("FALCON 9 BLOCK 5", "FALCON 9")
                            color: row.sel ? "#000000" : root.fg
                            font { family: root.sans; pixelSize: 12; letterSpacing: 1 }
                        }
                        Label { x: 24; y: 34; width: card.sideW - 24; elide: Text.ElideRight
                            color: row.sel ? "#000000" : root.dim
                            text: String(row.modelData.mission).toUpperCase() + " · " + String(row.modelData.loc ?? "").split(",")[0].toUpperCase() }
                    }
                }
                Item { width: 1; height: 8; visible: !root.rowsAlt }
                Label { visible: !root.rowsAlt; text: "OVERHEAD VALENCIA NOW  (≥10°)"; color: root.fg }
                Item { width: 1; height: 2; visible: !root.rowsAlt }
                Repeater {
                    model: root.orbit.sats ?? []
                    Item {   // one row: el° + name, click = select/deselect (inverted when selected)
                        required property var modelData
                        readonly property bool sel: root.selected === modelData.name
                        visible: !root.rowsAlt
                        width: card.sideW; height: 15
                        Rectangle { visible: parent.sel; x: -6; y: -2; width: card.sideW - 12; height: 18
                                    color: root.warn; radius: 3 }
                        Label { x: 0; width: 38; text: modelData.el + "°"
                                color: parent.sel ? "#000000" : root.fg }
                        Label { x: 48; width: card.sideW - 60; elide: Text.ElideRight
                                text: String(modelData.name).toUpperCase()
                                color: parent.sel ? "#000000" : root.dim }
                        MouseArea {
                            x: -6; y: -2; width: card.sideW - 12; height: 18
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { root.selLaunch = -1; root.clearCatalog(); root.selected = parent.sel ? "" : modelData.name }
                        }
                    }
                }
                Label { visible: !root.rowsAlt && (root.orbit.sats ?? []).length === 0; text: "NO BRIGHT SATELLITES ABOVE THE HORIZON" }
                Item { width: 1; height: 6; visible: !root.rowsAlt }
                Label { visible: !root.rowsAlt; text: "STATIONS"; color: root.fg }
                Repeater {
                    model: ["ISS", "CSS"]
                    Item {   // stations are listed even when below the horizon; click selects
                        required property string modelData
                        readonly property bool sel: root.selected === modelData
                        visible: !root.rowsAlt
                        width: card.sideW; height: 15
                        Rectangle { visible: parent.sel; x: -6; y: -2; width: card.sideW - 12; height: 18
                                    color: root.warn; radius: 3 }
                        Label { x: 0; width: 110; text: root.displayName(modelData).toUpperCase()
                                color: parent.sel ? "#000000" : root.fg }
                        Label { x: 110; width: 90; text: "EL " + (root.infoOf(modelData).el ?? "—") + "°"
                                color: parent.sel ? "#000000" : root.dim }
                        Label { x: 200; width: card.sideW - 212; elide: Text.ElideRight
                                text: "NORAD " + (root.infoOf(modelData).norad ?? "—")
                                color: parent.sel ? "#000000" : root.dim }
                        MouseArea {
                            x: -6; y: -2; width: card.sideW - 12; height: 18
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { root.selLaunch = -1; root.clearCatalog(); root.selected = parent.sel ? "" : modelData }
                        }
                    }
                }
            }
        }
    }
}
