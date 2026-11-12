// Decisions: the machine's live process tree on a branching galaxy.
// The galaxy is a balanced, deep tree grown from the centre (new shape each load), flattened
// and twisted into arms, with a slower dust disc behind it. Real processes are mapped onto it:
// systemd is the centre, every process sits on a branch below its parent's branch (processes
// with many children spread further down), threads sit at the tips under their process.
// Busy processes send pulses from the centre down their real ancestry and their branch tips
// glow with their CPU share; new processes flash; exited ones go dark. The busiest are labelled.
// Data: aeris-proctree (one JSON line a second from /proc, run only while this scene shows).
// Look inspired by the astraed.co homepage hero; code written for Qt Quick 3D.
import QtQuick
import QtQuick3D
import QtQuick3D.Helpers
import Quickshell.Io
import "lib.js" as L

Item {
    id: scene
    property real clock: 0
    readonly property int maxDepth: 7
    readonly property int fps: 15       // turns slowly; half the frames, half the cost
    readonly property real turnSeconds: 140

    // the galaxy (static skeleton)
    property var sk: []             // nodes: {parent, depth, p, kids: [indexes]}
    property real radius: 1
    property var polyCache: ({})    // skeleton index -> pulse polyline from the centre

    // live processes
    property var procs: ({})        // id -> {node, name, cpu, kind, parent}
    property var flashes: ({})      // skeleton index -> clock of a new process there
    property var pulses: []
    property var labels: []
    property real totalCpu: 0
    property int procCount: 0
    property int threadCount: 0
    property int ncpu: 1
    property int samples: 0

    // ---------------------------------------------------------------- the galaxy
    function build() {
        const r = L.rng(Math.floor(Math.random() * 2147483647))
        const ns = [{ parent: -1, depth: 0, p: [0, 0, 0], kids: [] }]
        function add(parent, d, len, depth) {
            const l = len * (0.85 + r() * 0.3), pp = ns[parent].p
            ns.push({ parent: parent, depth: depth, p: [pp[0] + d[0] * l, pp[1] + d[1] * l, pp[2] + d[2] * l], kids: [] })
            const me = ns.length - 1
            ns[parent].kids.push(me)
            grow(me, d, len * 0.84, depth + 1)
        }
        function grow(parent, dir, len, depth) {
            if (depth > scene.maxDepth) return
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
        for (let i = 0; i < 6; i++) {           // first branches: evenly over a sphere
            const y = 1 - 2 * (i + 0.5) / 6, rr = Math.sqrt(1 - y * y), th = i * 2.39996 + r() * 0.5
            add(0, L.norm([Math.cos(th) * rr + (r() - 0.5) * 0.3, y, Math.sin(th) * rr + (r() - 0.5) * 0.3]), 0.9, 1)
        }
        let rad = 0
        for (const n of ns) rad = Math.max(rad, Math.hypot(n.p[0], n.p[1], n.p[2]))
        for (const n of ns) {                   // flatten to a disc, twist with distance: galaxy arms
            const x = n.p[0], y = n.p[1] * 0.58, z = n.p[2], a = 1.3 * Math.hypot(x, z) / rad
            n.p = [x * Math.cos(a) - z * Math.sin(a), y, x * Math.sin(a) + z * Math.cos(a)]
        }
        sk = ns; radius = rad
        const pos = [], col = []
        for (let i = 1; i < ns.length; i++) {
            const c = curve(i), k = 0.055 + 0.13 * ns[i].depth / scene.maxDepth
            let prev = bez(c, 0)
            for (let s = 1; s <= 4; s++) { const q = bez(c, s / 4); pos.push(L.v3(prev), L.v3(q)); col.push(L.ink(k), L.ink(k)); prev = q }
        }
        tree.positions = pos; tree.colors = col
        const tp = [], tc = []
        for (const n of ns) if (!n.kids.length) { tp.push(L.v3(n.p)); tc.push(L.ink(0.22)) }
        leafDots.positions = tp; leafDots.colors = tc
        const dp = [], dc = []
        for (let i = 0; i < 1400; i++) {
            const th = r() * 6.283, rr = rad * Math.sqrt(r()) * 1.1, y = (r() + r() + r() - 1.5) * rad * 0.22
            const a = 1.3 * rr / rad
            dp.push(Qt.vector3d(Math.cos(th + a) * rr, y, Math.sin(th + a) * rr))
            dc.push(L.ink(0.05 + Math.pow(r(), 3) * 0.28))
        }
        dust.positions = dp; dust.colors = dc
    }
    function mid(a, b) { return [(a[0] + b[0]) / 2, (a[1] + b[1]) / 2, (a[2] + b[2]) / 2] }
    function curve(i) {                         // parent's middle -> parent -> own middle (or tip)
        const me = sk[i], p = sk[me.parent], g = p.parent >= 0 ? sk[p.parent] : null
        return [g ? mid(g.p, p.p) : p.p, p.p, me.kids.length ? mid(p.p, me.p) : me.p]
    }
    function bez(c, u) {
        const w0 = (1 - u) * (1 - u), w1 = 2 * (1 - u) * u, w2 = u * u
        return [w0 * c[0][0] + w1 * c[1][0] + w2 * c[2][0], w0 * c[0][1] + w1 * c[1][1] + w2 * c[2][1], w0 * c[0][2] + w1 * c[1][2] + w2 * c[2][2]]
    }
    function polyline(i) {                      // centre -> skeleton node i, sampled, with distances
        if (polyCache[i]) return polyCache[i]
        const chain = []
        for (let m = i; m > 0; m = sk[m].parent) chain.unshift(m)
        const pts = []
        for (const m of chain) { const c = curve(m); for (let s = pts.length ? 1 : 0; s <= 6; s++) pts.push(bez(c, s / 6)) }
        const dist = [0]
        for (let k = 1; k < pts.length; k++) dist.push(dist[k - 1] + Math.hypot(pts[k][0] - pts[k - 1][0], pts[k][1] - pts[k - 1][1], pts[k][2] - pts[k - 1][2]))
        return polyCache[i] = { pts: pts, dist: dist, total: dist[dist.length - 1] }
    }

    // ---------------------------------------------------------------- mapping processes onto it
    function hash(n, salt) {
        let x = (n * 2654435761 + salt * 40503) >>> 0
        x ^= x >>> 15; x = Math.imul(x, 2246822519) >>> 0; x ^= x >>> 13
        x = Math.imul(x, 3266489917) >>> 0; x ^= x >>> 16
        return (x >>> 0) / 4294967296
    }
    function descend(from, id, levels) {        // walk `levels` steps down, choosing by the id
        let n = from
        for (let l = 0; l < levels && sk[n].kids.length; l++) n = sk[n].kids[Math.floor(hash(id, l + 1) * sk[n].kids.length)]
        return n
    }

    function onSample(j) {
        const old = procs, ps = {}, byParent = {}
        ncpu = j.ncpu || 1
        for (const r of j.procs) (byParent[r[1]] = byParent[r[1]] || []).push(r)
        let tc = 0, pc = 0, th = 0
        // systemd (1) and the kernel's thread parent (2) both start at the centre
        const queue = [[1, 0], [2, 0]]
        for (const r of (byParent[0] || [])) ps[r[0]] = { node: 0, name: r[2], cpu: r[3], kind: r[4], parent: 0 }
        while (queue.length) {
            const [pid, node] = queue.shift()
            const kids = byParent[pid] || []
            // a process with many children spreads them further down its part of the galaxy
            const levels = kids.length >= 24 ? 4 : kids.length >= 8 ? 3 : kids.length >= 3 ? 2 : 1
            for (const r of kids) {
                const id = r[0]
                if (id === pid || ps[id]) continue
                const n = r[4] === 2 ? descend(node, id, 12) : descend(node, id, levels)   // threads: down to a tip
                ps[id] = { node: n, name: r[2], cpu: r[3], kind: r[4], parent: pid }
                if (samples > 0 && !old[id]) flashes[n] = clock
                tc += r[3]
                if (r[4] === 2) th++; else pc++
                if (r[4] !== 2) queue.push([id, n])
            }
        }
        procs = ps
        totalCpu = tc; procCount = pc; threadCount = th
        samples++
        firePulses()
        drawGlow()
        const busy = []
        for (const id in ps) if (ps[id].cpu >= 1) busy.push(ps[id])
        busy.sort((a, b) => b.cpu - a.cpu)
        // one label per branch tip: processes sharing a tip are listed together
        const byNode = {}, out = []
        for (const p of busy) {
            const t = (p.kind === 2 && ps[p.parent] ? ps[p.parent].name + " › " : "") + p.name + "  " + Math.round(p.cpu) + "%"
            if (byNode[p.node]) { if (byNode[p.node].n++ < 2) byNode[p.node].text += "   " + t; continue }
            if (out.length >= 6) continue
            byNode[p.node] = { p: sk[p.node].p, text: t, n: 1 }
            out.push(byNode[p.node])
        }
        labels = out
    }

    function firePulses() {
        let budget = 40 - pulses.length
        const busy = []
        for (const id in procs) if (procs[id].cpu >= 0.8 && procs[id].node > 0) busy.push(procs[id])
        busy.sort((a, b) => b.cpu - a.cpu)
        for (const p of busy) {
            const count = Math.min(2, Math.ceil(p.cpu / 30))
            for (let i = 0; i < count && budget > 0; i++, budget--)
                pulses.push({ t0: clock + Math.random(), line: polyline(p.node), k: 0.25 + 0.5 * Math.min(1, p.cpu / 40) })
        }
    }

    // ---------------------------------------------------------------- per-sample and per-frame meshes
    function drawGlow() {
        // branch tips of busy processes glow; new processes flash where they landed
        const k = {}
        for (const id in procs) {
            const p = procs[id]
            if (p.cpu > 0.3 && p.node > 0) k[p.node] = Math.max(k[p.node] || 0, 0.2 + 0.7 * Math.min(1, p.cpu / 50))
        }
        for (const n in flashes) {
            const f = Math.max(0, 1 - (clock - flashes[n]) / 2.5)
            if (f <= 0) { delete flashes[n]; continue }
            k[n] = Math.max(k[n] || 0, 0.9 * f)
        }
        const pos = [], col = []
        for (const n in k) { pos.push(L.v3(sk[n].p)); col.push(L.ink(k[n])) }
        if (!pos.length) { pos.push(Qt.vector3d(0, 0, 0)); col.push(L.ink(0)) }
        glow.positions = pos; glow.colors = col
    }
    function drawPulses() {
        const pos = [], col = [], now = clock, run = 1.5, keep = []
        for (const p of pulses) {
            const age = now - p.t0
            if (age < 0) { keep.push(p); continue }
            if (age > run + 0.5) continue
            keep.push(p)
            const ln = p.line, u = Math.min(1, age / run)
            const head = (u < 0.5 ? 2 * u * u : 1 - Math.pow(-2 * u + 2, 2) / 2) * ln.total
            const tail = ln.total * 0.24, fade = Math.max(0, 1 - Math.max(0, age - run) / 0.5)
            for (let i = 1; i < ln.pts.length; i++) {
                if (ln.dist[i] > head) break
                const f = 1 - (head - ln.dist[i]) / tail
                if (f <= 0) continue
                const k = p.k * f * f * fade
                pos.push(L.v3(ln.pts[i - 1]), L.v3(ln.pts[i])); col.push(L.ink(k), L.ink(k))
            }
        }
        pulses = keep
        if (!pos.length) { pos.push(Qt.vector3d(0, 0, 0), Qt.vector3d(0, 0, 0)); col.push(L.ink(0), L.ink(0)) }
        signal.positions = pos; signal.colors = col
    }

    Component.onCompleted: build()
    onClockChanged: {
        drawPulses()
        if (Object.keys(flashes).length) drawGlow()
    }

    Process {
        command: ["sh", "-c", "exec \"$HOME/.local/bin/aeris-proctree\" --interval 1"]
        running: true
        stdout: SplitParser {
            onRead: data => { try { scene.onSample(JSON.parse(data)) } catch (e) { console.warn("proctree:", e) } }
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
        PerspectiveCamera {
            id: cam
            readonly property real dist: scene.radius * 1.85
            position: Qt.vector3d(0, dist * Math.sin(0.38), dist * Math.cos(0.38))
            eulerRotation.x: -0.38 * 180 / Math.PI
            fieldOfView: 50; clipNear: 0.01; clipFar: 1000
        }
        Node {
            id: treeNode
            eulerRotation.y: scene.clock / scene.turnSeconds * 360
            Model { geometry: ProceduralMesh { id: tree; primitiveMode: ProceduralMesh.Lines } materials: ink }
            Model { geometry: ProceduralMesh { id: leafDots; primitiveMode: ProceduralMesh.Points } materials: inkDust }
            Model { geometry: ProceduralMesh { id: signal; primitiveMode: ProceduralMesh.Lines } materials: ink }
            Model { geometry: ProceduralMesh { id: glow; primitiveMode: ProceduralMesh.Points } materials: inkGlow }
        }
        Node {
            eulerRotation.y: scene.clock / scene.turnSeconds * 360 * 0.8   // dust turns slower: parallax
            Model { geometry: ProceduralMesh { id: dust; primitiveMode: ProceduralMesh.Points } materials: inkDust }
        }
    }
    CustomMaterial {            // near side bright, far side dim, as if seen through depth (fade.vert/.frag)
        id: ink
        property real fadeNear: cam.dist - scene.radius * 0.9
        property real fadeFar: cam.dist + scene.radius * 1.6
        property real pointSize: 1
        property real nearBoost: 1.6
        property real floorLevel: 0.28
        shadingMode: CustomMaterial.Unshaded
        sourceBlend: CustomMaterial.One
        destinationBlend: CustomMaterial.OneMinusSrcColor
        cullMode: Material.NoCulling
        depthDrawMode: Material.NeverDepthDraw
        vertexShader: "fade.vert"
        fragmentShader: "fade.frag"
    }
    PrincipledMaterial { id: inkGlow; lighting: PrincipledMaterial.NoLighting; vertexColorsEnabled: true; blendMode: PrincipledMaterial.Screen; pointSize: 3 }
    PrincipledMaterial { id: inkDust; lighting: PrincipledMaterial.NoLighting; vertexColorsEnabled: true; blendMode: PrincipledMaterial.Screen; pointSize: 1.5 }

    // ---------------------------------------------------------------- 2D labels and totals
    Repeater {
        model: scene.labels.length
        Text {
            required property int index
            readonly property var l: scene.labels[index]
            readonly property vector3d world: (scene.clock, l) ? treeNode.mapPositionToScene(Qt.vector3d(l.p[0], l.p[1], l.p[2])) : Qt.vector3d(0, 0, 0)
            readonly property vector3d sp: view.mapFrom3DScene(world)
            visible: !!l
            x: sp.x + 8; y: sp.y - height / 2
            color: Qt.rgba(0.85, 0.85, 0.84, 0.65)
            font { family: "Söhne"; pixelSize: 11 }
            text: l ? l.text : ""
        }
    }
    Text {
        anchors { left: parent.left; bottom: parent.bottom; leftMargin: 24; bottomMargin: 20 }
        color: Qt.rgba(0.8, 0.8, 0.79, 0.7)
        font { family: "Söhne"; pixelSize: 12; letterSpacing: 1 }
        text: scene.procCount + " processes  ·  " + scene.threadCount + " threads  ·  CPU "
            + Math.round(scene.totalCpu / scene.ncpu) + "%"
    }
}
