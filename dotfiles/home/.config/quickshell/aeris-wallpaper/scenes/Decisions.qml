// Decisions: one decision at the centre, consequences branching out in every direction,
// flattened and twisted into galaxy arms around a dense core. A slower dust disc turns behind
// it for depth. Every few seconds a signal runs from the centre to an outcome near the edge and
// spreads to the branches around it. A new shape every time the scene loads.
// (Inspired by the astraed.co homepage hero; written from scratch for Qt Quick 3D.)
import QtQuick
import QtQuick3D
import QtQuick3D.Helpers
import "lib.js" as L

Item {
    id: scene
    property real clock: 0
    readonly property int maxDepth: 8
    readonly property real turnSeconds: 140

    property var nodes: []
    property var leaves: []
    property real radius: 1
    property var path: []
    property real pathStart: -100
    readonly property real runS: 1.5
    readonly property real spreadS: 1.1
    readonly property real gapS: 0.7

    // ---------------------------------------------------------------- build
    function build() {
        const r = L.rng(Math.floor(Math.random() * 2147483647))
        const ns = [{ parent: -1, depth: 0, p: [0, 0, 0], kids: 0 }], lv = []
        function add(parent, d, len, depth) {
            const l = len * (0.85 + r() * 0.3), pp = ns[parent].p
            ns.push({ parent: parent, depth: depth, p: [pp[0] + d[0] * l, pp[1] + d[1] * l, pp[2] + d[2] * l], kids: 0 })
            const me = ns.length - 1
            ns[parent].kids++
            grow(me, d, len * 0.84, depth + 1)
        }
        function grow(parent, dir, len, depth) {
            if (depth > scene.maxDepth) { lv.push(parent); return }
            const n = r() < 0.4 ? 3 : 2
            const u = L.norm(L.cross(dir, Math.abs(dir[1]) < 0.9 ? [0, 1, 0] : [1, 0, 0])), v = L.cross(dir, u)
            const turn = r() * Math.PI * 2
            for (let i = 0; i < n; i++) {
                if (depth > 6 && r() < 0.1) continue
                const az = turn + i * Math.PI * 2 / n + (r() - 0.5) * 0.6
                const tilt = 0.3 + r() * 0.22
                const d = L.norm([0, 1, 2].map(k => dir[k] * Math.cos(tilt) + (u[k] * Math.cos(az) + v[k] * Math.sin(az)) * Math.sin(tilt)))
                add(parent, d, len, depth)
            }
        }
        for (let i = 0; i < 6; i++) {           // first consequences: evenly over a sphere
            const y = 1 - 2 * (i + 0.5) / 6, rr = Math.sqrt(1 - y * y), th = i * 2.39996 + r() * 0.5
            add(0, L.norm([Math.cos(th) * rr + (r() - 0.5) * 0.3, y, Math.sin(th) * rr + (r() - 0.5) * 0.3]), 0.9, 1)
        }
        let rad = 0
        for (const n of ns) rad = Math.max(rad, Math.hypot(n.p[0], n.p[1], n.p[2]))
        for (const n of ns) {                   // flatten to a disc, twist with distance: galaxy arms
            let x = n.p[0], y = n.p[1] * 0.58, z = n.p[2]
            const a = 1.3 * Math.hypot(x, z) / rad
            n.p = [x * Math.cos(a) - z * Math.sin(a), y, x * Math.sin(a) + z * Math.cos(a)]
        }
        for (const l of lv) ns[l].spark = r() < 0.12 ? { phase: r() * 6.283, period: 3.2 + r() * 4.8, peak: 0.35 + r() * 0.3 } : null
        nodes = ns; leaves = lv; radius = rad

        // branches as smooth curves: parent's middle -> parent -> own middle (or tip)
        const pos = [], col = []
        for (let i = 1; i < ns.length; i++) {
            const c = curve(i), k = 0.035 + 0.09 * ns[i].depth / scene.maxDepth
            let prev = bez(c, 0)
            for (let s = 1; s <= 5; s++) {
                const q = bez(c, s / 5)
                pos.push(L.v3(prev), L.v3(q)); col.push(L.ink(k), L.ink(k))
                prev = q
            }
        }
        tree.positions = pos; tree.colors = col
        const tp = [], tc = []
        for (const l of lv) { tp.push(L.v3(ns[l].p)); tc.push(L.ink(0.3)) }
        tips.positions = tp; tips.colors = tc
        const dp = [], dc = []
        for (let i = 0; i < 1400; i++) {
            const th = r() * 6.283, rr = rad * Math.sqrt(r()) * 1.1, y = (r() + r() + r() - 1.5) * rad * 0.22
            const a = 1.3 * rr / rad
            dp.push(Qt.vector3d(Math.cos(th + a) * rr, y, Math.sin(th + a) * rr))
            dc.push(L.ink(0.06 + Math.pow(r(), 3) * 0.3))
        }
        dust.positions = dp; dust.colors = dc
    }
    function curve(i) {
        const n = nodes.length ? nodes : null
        const ns = n || [], me = ns[i], p = ns[me.parent], g = p.parent >= 0 ? ns[p.parent] : null
        const a = g ? mid(g.p, p.p) : p.p
        return [a, p.p, me.kids ? mid(p.p, me.p) : me.p]
    }
    function mid(a, b) { return [(a[0] + b[0]) / 2, (a[1] + b[1]) / 2, (a[2] + b[2]) / 2] }
    function bez(c, u) {
        const w0 = (1 - u) * (1 - u), w1 = 2 * (1 - u) * u, w2 = u * u
        return [0, 1, 2].map(k => w0 * c[0][k] + w1 * c[1][k] + w2 * c[2][k])
    }

    // ---------------------------------------------------------------- signal
    function pick() {
        // an outcome far from the centre, then the chain of branches back to it
        const far = leaves.slice().sort((a, b) => Math.hypot(nodes[b].p[0], nodes[b].p[2]) - Math.hypot(nodes[a].p[0], nodes[a].p[2]))
        const from = far.slice(0, Math.max(8, Math.floor(far.length * 0.15)))
        let n = from[Math.floor(Math.random() * from.length)]
        const p = []
        while (n >= 0) { p.unshift(n); n = nodes[n].parent }
        path = p
        pathStart = clock
    }
    function drawSignal() {
        const age = clock - pathStart, pos = [], col = []
        if (path.length > 1 && age < runS + spreadS) {
            const pts = [], dist = [0]
            for (let i = 1; i < path.length; i++) {
                const c = curve(path[i])
                for (let s = pts.length ? 1 : 0; s <= 8; s++) pts.push(bez(c, s / 8))
            }
            for (let i = 1; i < pts.length; i++)
                dist.push(dist[i - 1] + Math.hypot(pts[i][0] - pts[i - 1][0], pts[i][1] - pts[i - 1][1], pts[i][2] - pts[i - 1][2]))
            const total = dist[dist.length - 1], u = Math.min(1, age / runS)
            const head = (u < 0.5 ? 2 * u * u : 1 - Math.pow(-2 * u + 2, 2) / 2) * total, tail = total * 0.24
            const fade = Math.max(0, 1 - Math.max(0, age - runS) / 0.5)
            for (let i = 1; i < pts.length && dist[i] <= head; i++) {
                const f = 1 - (head - dist[i]) / tail
                if (f <= 0) continue
                pos.push(L.v3(pts[i - 1]), L.v3(pts[i]))
                col.push(L.ink(0.55 * f * f * fade), L.ink(0.55 * f * f * fade))
            }
            if (age >= runS) {                  // arrival: the neighbouring branches flicker
                const after = age - runS, onPath = {}
                for (const k of path) onPath[k] = true
                const near = path.slice(-4, -1)
                for (let i = 1; i < nodes.length; i++) {
                    if (onPath[i] || near.indexOf(nodes[i].parent) < 0) continue
                    const k = Math.sin(Math.min(1, after / spreadS) * Math.PI) * 0.3 * (0.75 + 0.25 * Math.sin(after * 50 + i))
                    const c = curve(i)
                    let prev = bez(c, 0)
                    for (let s = 1; s <= 5; s++) { const q = bez(c, s / 5); pos.push(L.v3(prev), L.v3(q)); col.push(L.ink(k), L.ink(k)); prev = q }
                }
            }
        }
        if (!pos.length) { pos.push(Qt.vector3d(0, 0, 0), Qt.vector3d(0, 0, 0)); col.push(L.ink(0), L.ink(0)) }
        signal.positions = pos; signal.colors = col
    }
    function drawSparks() {
        const pos = [], col = []
        for (const l of leaves) {
            const s = nodes[l].spark
            if (!s) continue
            const on = Math.pow(Math.max(0, Math.sin(s.phase + clock / s.period * 6.283)), 4)
            pos.push(L.v3(nodes[l].p)); col.push(L.ink(s.peak * on))
        }
        sparks.positions = pos; sparks.colors = col
    }

    Component.onCompleted: build()
    onClockChanged: {
        if (clock - pathStart > runS + spreadS + gapS) pick()
        drawSignal()
        drawSparks()
    }

    // ---------------------------------------------------------------- scene
    View3D {
        anchors.fill: parent
        environment: SceneEnvironment {
            backgroundMode: SceneEnvironment.Color
            clearColor: "black"
            antialiasingMode: SceneEnvironment.MSAA
            antialiasingQuality: SceneEnvironment.High
        }
        PerspectiveCamera {
            readonly property real dist: scene.radius * 1.85
            position: Qt.vector3d(0, dist * Math.sin(0.38), dist * Math.cos(0.38))
            eulerRotation.x: -0.38 * 180 / Math.PI
            fieldOfView: 50
            clipNear: 0.01
            clipFar: 1000
        }
        Node {
            eulerRotation.y: scene.clock / scene.turnSeconds * 360
            Model { geometry: ProceduralMesh { id: tree; primitiveMode: ProceduralMesh.Lines } materials: ink }
            Model { geometry: ProceduralMesh { id: tips; primitiveMode: ProceduralMesh.Points } materials: inkPoints }
            Model { geometry: ProceduralMesh { id: sparks; primitiveMode: ProceduralMesh.Points } materials: inkSparks }
            Model { geometry: ProceduralMesh { id: signal; primitiveMode: ProceduralMesh.Lines } materials: ink }
        }
        Node {
            eulerRotation.y: scene.clock / scene.turnSeconds * 360 * 0.8   // dust turns slower: parallax
            Model { geometry: ProceduralMesh { id: dust; primitiveMode: ProceduralMesh.Points } materials: inkPoints }
        }
    }
    PrincipledMaterial { id: ink; lighting: PrincipledMaterial.NoLighting; vertexColorsEnabled: true; blendMode: PrincipledMaterial.Screen; cullMode: Material.NoCulling }
    PrincipledMaterial { id: inkPoints; lighting: PrincipledMaterial.NoLighting; vertexColorsEnabled: true; blendMode: PrincipledMaterial.Screen; pointSize: 1.5 }
    PrincipledMaterial { id: inkSparks; lighting: PrincipledMaterial.NoLighting; vertexColorsEnabled: true; blendMode: PrincipledMaterial.Screen; pointSize: 3 }
}
