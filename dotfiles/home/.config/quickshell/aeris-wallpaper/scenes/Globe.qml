// Globe: a slowly turning wireframe Earth with every network connection of this machine.
// Graticule every 15°, Natural Earth coastlines, real day/night from the subsolar point, and a
// light on home (Valencia, as the orbit map).
//
// Live traffic comes from `aeris-netmap` (one JSON line a second; runs only while this scene is
// on screen): each remote address is an arc from home to where it is (offline DB-IP database).
// Pulses run along the arc in the direction the bytes flow, faster and more often the more
// traffic there is; incoming connections (to a port we listen on) are dashed. New connections
// flash at their far end; closed ones fade out. The busiest are labelled, and a corner line
// shows the totals.
import QtQuick
import QtQuick3D
import QtQuick3D.Helpers
import Quickshell.Io
import "lib.js" as L
import "land.js" as Land

Item {
    id: scene
    property real clock: 0
    readonly property real homeLat: 39.47
    readonly property real homeLon: -0.38
    readonly property real centerLon: -25
    readonly property real swayDeg: 70
    readonly property real swaySeconds: 600
    property var verts: []          // graticule + coast unit vectors, in pairs
    property var weights: []
    property real lastSun: -1000

    // live network state, keyed by remote ip
    property var flows: ({})
    property real totalRx: 0
    property real totalTx: 0
    property int connCount: 0
    property int localCount: 0
    property var labels: []         // top flows for the 2D labels
    property real lastArcs: -1

    function xyz(lat, lon) {        // y up, lon 0 facing +z
        const la = lat * Math.PI / 180, lo = lon * Math.PI / 180
        return [Math.cos(la) * Math.sin(lo), Math.sin(la), Math.cos(la) * Math.cos(lo)]
    }

    // ---------------------------------------------------------------- base globe
    function build() {
        const v = [], w = []
        function seg(a, b, k) { v.push(a, b); w.push(k, k) }
        for (let lat = -75; lat <= 75; lat += 15)
            for (let lon = -180; lon < 180; lon += 3) seg(xyz(lat, lon), xyz(lat, lon + 3), lat === 0 ? 0.13 : 0.07)
        for (let lon = -180; lon < 180; lon += 15)
            for (let lat = -90; lat < 90; lat += 3) seg(xyz(lat, lon), xyz(lat + 3, lon), 0.07)
        for (const ring of Land.rings)
            for (let i = 1; i < ring.length; i++) seg(xyz(ring[i - 1][1], ring[i - 1][0]), xyz(ring[i][1], ring[i][0]), 0.34)
        verts = v; weights = w
        const pos = []
        for (const p of v) pos.push(L.v3(p))
        lines.positions = pos
        home.position = L.v3(xyz(homeLat, homeLon).map(c => c * 1.004))
        shade()
    }
    function sunVector() {
        const d = new Date(), day = (d - Date.UTC(d.getUTCFullYear(), 0, 0)) / 864e5
        const decl = -23.44 * Math.cos(2 * Math.PI / 365 * (day + 10))
        const hours = d.getUTCHours() + d.getUTCMinutes() / 60
        return xyz(decl, (12 - hours) * 15)
    }
    function shade() {
        const s = sunVector(), col = []
        for (let i = 0; i < verts.length; i++) {
            const p = verts[i], dot = p[0] * s[0] + p[1] * s[1] + p[2] * s[2]
            const day = Math.min(1, Math.max(0, (dot + 0.12) / 0.24))
            col.push(L.ink(weights[i] * (0.28 + 0.72 * day)))
        }
        lines.colors = col
        lastSun = clock
    }

    // ---------------------------------------------------------------- arcs
    // Great circle from home to the remote point, lifted above the surface in the middle.
    function arcPoint(a, b, w, u, lift) {
        const s = Math.sin(w), k0 = Math.sin((1 - u) * w) / s, k1 = Math.sin(u * w) / s
        const h = 1.003 + lift * Math.sin(Math.PI * u)
        return [(a[0] * k0 + b[0] * k1) * h, (a[1] * k0 + b[1] * k1) * h, (a[2] * k0 + b[2] * k1) * h]
    }
    function activity(f) { return Math.min(1, Math.log10(1 + f.rx + f.tx) / 6) }    // 0..1, 1 MB/s = 1

    function onNet(j) {
        const now = clock, seen = {}, fl = flows
        let rx = 0, tx = 0, n = 0, local = 0
        const home3 = xyz(homeLat, homeLon)
        for (const f of j.flows) {
            seen[f.ip] = true
            rx += f.rx; tx += f.tx
            if (f.kind === "lan" || (Math.abs(f.lat - homeLat) < 0.05 && Math.abs(f.lon - homeLon) < 0.05)) { local += f.n; continue }
            n += f.n
            let e = fl[f.ip]
            if (!e) {
                const b = xyz(f.lat, f.lon), w = Math.acos(Math.max(-1, Math.min(1, home3[0] * b[0] + home3[1] * b[1] + home3[2] * b[2])))
                e = fl[f.ip] = { born: now, b: b, w: Math.max(w, 1e-4), lift: 0.04 + 0.32 * w / Math.PI, pulses: [], next: now }
            }
            e.rx = f.rx; e.tx = f.tx; e.dir = f.dir; e.kind = f.kind; e.n = f.n
            e.place = f.place; e.cc = f.cc; e.name = f.name; e.seen = now; e.gone = 0
        }
        for (const ip in fl)
            if (!seen[ip] && !fl[ip].gone) fl[ip].gone = now
        totalRx = rx; totalTx = tx; connCount = n; localCount = local
        // labels: the busiest few, then the newest
        const list = Object.keys(fl).map(ip => [ip, fl[ip]]).filter(p => !p[1].gone)
        list.sort((a, b) => (b[1].rx + b[1].tx) - (a[1].rx + a[1].tx) || b[1].born - a[1].born)
        labels = list.slice(0, 7)
        lastArcs = -1
    }

    function drawArcs() {
        // static arcs: rebuilt at most twice a second (fades, new and closed flows)
        const pos = [], col = [], tips = [], tipc = [], home3 = xyz(homeLat, homeLon), now = clock
        for (const ip in flows) {
            const e = flows[ip]
            let k = 0.07 + 0.25 * activity(e)
            if (e.kind === "tailnet") k += 0.08
            const age = now - e.born
            k *= Math.min(1, age / 0.8)                                      // fade in
            if (e.gone) { k *= Math.max(0, 1 - (now - e.gone) / 6); if (now - e.gone > 6) { delete flows[ip]; continue } }
            const segs = 36, dashed = e.dir === "in"
            let prev = arcPoint(home3, e.b, e.w, 0, e.lift)
            for (let i = 1; i <= segs; i++) {
                const q = arcPoint(home3, e.b, e.w, i / segs, e.lift)
                if (!dashed || i % 2) { pos.push(L.v3(prev), L.v3(q)); col.push(L.ink(k), L.ink(k)) }
                prev = q
            }
            const flash = age < 2 ? 1 - age / 2 : 0
            tips.push(L.v3(e.b.map(c => c * 1.004))); tipc.push(L.ink(Math.min(1, k * 2.2 + flash)))
        }
        if (!pos.length) { pos.push(Qt.vector3d(0, 0, 0), Qt.vector3d(0, 0, 0)); col.push(L.ink(0), L.ink(0)) }
        if (!tips.length) { tips.push(Qt.vector3d(0, 0, 0)); tipc.push(L.ink(0)) }
        arcs.positions = pos; arcs.colors = col
        ends.positions = tips; ends.colors = tipc
        lastArcs = now
    }

    function drawPulses() {
        // every frame: comets travelling along the arcs, out from home or in toward it
        const pos = [], col = [], home3 = xyz(homeLat, homeLon), now = clock
        for (const ip in flows) {
            const e = flows[ip]
            if (e.gone) { e.pulses = []; continue }
            const act = activity(e)
            const rate = (e.rx + e.tx) > 0 ? 0.25 + 3.5 * act : 0.05            // pulses per second
            if (now >= e.next) {
                const inbound = e.rx > e.tx * 1.5 || (e.rx === e.tx && e.dir === "in")
                e.pulses.push({ t0: now, inbound: inbound, k: 0.35 + 0.65 * act })
                e.next = now + (1 / rate) * (0.6 + Math.random() * 0.8)
            }
            const dur = 0.9 + 1.4 * e.w / Math.PI
            e.pulses = e.pulses.filter(p => now - p.t0 < dur)
            for (const p of e.pulses) {
                const u = (now - p.t0) / dur
                for (let s = 0; s < 4; s++) {                                      // head + fading tail
                    let u0 = u - s * 0.025, u1 = u - (s + 1) * 0.025
                    if (u1 < 0) break
                    if (p.inbound) { u0 = 1 - u0; u1 = 1 - u1 }
                    const k = p.k * (1 - s / 4)
                    pos.push(L.v3(arcPoint(home3, e.b, e.w, u0, e.lift)), L.v3(arcPoint(home3, e.b, e.w, u1, e.lift)))
                    col.push(L.ink(k), L.ink(k))
                }
            }
        }
        if (!pos.length) { pos.push(Qt.vector3d(0, 0, 0), Qt.vector3d(0, 0, 0)); col.push(L.ink(0), L.ink(0)) }
        pulses.positions = pos; pulses.colors = col
    }

    function rate(b) {
        if (b >= 1e6) return (b / 1e6).toFixed(1) + " MB/s"
        if (b >= 1e3) return Math.round(b / 1e3) + " kB/s"
        return Math.round(b) + " B/s"
    }

    Component.onCompleted: build()
    onClockChanged: {
        if (clock - lastSun > 60) shade()
        if (lastArcs < 0 || clock - lastArcs > 0.5) drawArcs()
        drawPulses()
    }

    Process {
        command: ["sh", "-c", "exec \"$HOME/.local/bin/aeris-netmap\" --interval 1"]
        running: true
        stdout: SplitParser {
            onRead: data => { try { scene.onNet(JSON.parse(data)) } catch (e) {} }
        }
    }

    // ---------------------------------------------------------------- 3D
    View3D {
        id: view
        anchors.fill: parent
        camera: cam
        environment: SceneEnvironment {
            backgroundMode: SceneEnvironment.Color; clearColor: "black"
            antialiasingMode: SceneEnvironment.MSAA; antialiasingQuality: SceneEnvironment.High
        }
        PerspectiveCamera { id: cam; position: Qt.vector3d(0, 0.75, 3.5); eulerRotation.x: -12; fieldOfView: 40; clipNear: 0.01 }
        Node {
            eulerRotation.z: 23.44 * 0.4
            Node {
                id: earth
                // sway slowly between the Americas and Asia, centred on the Atlantic and Europe,
                // where most of the traffic from here goes (the longitude facing the camera equals this angle)
                eulerRotation.y: scene.centerLon + scene.swayDeg * Math.sin(scene.clock * 2 * Math.PI / scene.swaySeconds)
                Model { geometry: ProceduralMesh { id: lines; primitiveMode: ProceduralMesh.Lines } materials: inkLines }
                Model { geometry: ProceduralMesh { id: arcs; primitiveMode: ProceduralMesh.Lines } materials: inkLines }
                Model { geometry: ProceduralMesh { id: pulses; primitiveMode: ProceduralMesh.Lines } materials: inkLines }
                Model { geometry: ProceduralMesh { id: ends; primitiveMode: ProceduralMesh.Points } materials: inkDots }
                Model {
                    id: home
                    geometry: ProceduralMesh { id: homeDot; primitiveMode: ProceduralMesh.Points; positions: [Qt.vector3d(0, 0, 0)] }
                    materials: PrincipledMaterial { lighting: PrincipledMaterial.NoLighting; vertexColorsEnabled: true; blendMode: PrincipledMaterial.Screen; pointSize: 4 }
                }
            }
        }
    }
    PrincipledMaterial { id: inkLines; lighting: PrincipledMaterial.NoLighting; vertexColorsEnabled: true; blendMode: PrincipledMaterial.Screen }
    PrincipledMaterial { id: inkDots; lighting: PrincipledMaterial.NoLighting; vertexColorsEnabled: true; blendMode: PrincipledMaterial.Screen; pointSize: 3 }
    Binding { target: homeDot; property: "colors"; value: [L.ink(0.3 + 0.6 * Math.pow(Math.max(0, Math.sin(scene.clock * 1.6)), 6))] }

    // ---------------------------------------------------------------- 2D labels and totals
    Repeater {
        model: scene.labels.length
        Text {
            id: lab
            required property int index
            readonly property var entry: scene.labels[index]
            readonly property var f: entry ? entry[1] : null
            // re-evaluated every frame through scene.clock; hidden on the far side of the globe
            readonly property vector3d world: (scene.clock, f) ? earth.mapPositionToScene(Qt.vector3d(f.b[0] * 1.02, f.b[1] * 1.02, f.b[2] * 1.02)) : Qt.vector3d(0, 0, -10)
            readonly property vector3d sp: view.mapFrom3DScene(world)
            readonly property bool front: world.z > 0.05
            visible: f !== null && front
            x: sp.x + 8; y: sp.y - height / 2
            color: Qt.rgba(0.85, 0.85, 0.84, front ? 0.75 : 0)
            font { family: "Söhne"; pixelSize: 11 }
            text: !f ? "" : (f.dir === "in" ? "← " : "→ ") + (f.place || f.cc || entry[0]) + (f.name ? "  ·  " + f.name : "")
                + ((f.rx + f.tx) > 0 ? "  ·  " + scene.rate(f.rx + f.tx) : "")
        }
    }
    Text {
        anchors { left: parent.left; bottom: parent.bottom; leftMargin: 24; bottomMargin: 20 }
        color: Qt.rgba(0.8, 0.8, 0.79, 0.7)
        font { family: "Söhne"; pixelSize: 12; letterSpacing: 1 }
        text: "↓ " + scene.rate(scene.totalRx) + "   ↑ " + scene.rate(scene.totalTx)
            + "   ·   " + scene.connCount + " connections" + (scene.localCount ? "  +" + scene.localCount + " local" : "")
    }
}
