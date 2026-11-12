// Constellation: a slowly turning sphere of stars, each linked to its nearest neighbours by
// faint lines, like star charts. Stars twinkle; now and then a link brightens and fades, as if
// two stars were talking.
import QtQuick
import QtQuick3D
import QtQuick3D.Helpers
import "lib.js" as L

Item {
    id: scene
    property real clock: 0
    property var stars: []
    property var links: []
    property int lit: -1
    property real litAt: -100

    function build() {
        const r = L.rng(Math.floor(Math.random() * 2147483647)), s = []
        for (let i = 0; i < 260; i++) {
            const u = r() * 2 - 1, th = r() * 6.283, rad = 2.2 + Math.pow(r(), 0.6) * 1.6 * (r() < 0.5 ? 1 : 0.7)
            const q = Math.sqrt(1 - u * u)
            s.push({ p: [q * Math.cos(th) * rad, u * rad * 0.8, q * Math.sin(th) * rad], b: 0.45 + Math.pow(r(), 3) * 0.55,
                     tw: r() * 6.283, per: 2 + r() * 5 })
        }
        const ls = [], seen = {}
        for (let i = 0; i < s.length; i++) {          // 2-3 nearest neighbours each, if close enough
            const d = []
            for (let j = 0; j < s.length; j++) if (j !== i)
                d.push([Math.hypot(s[i].p[0] - s[j].p[0], s[i].p[1] - s[j].p[1], s[i].p[2] - s[j].p[2]), j])
            d.sort((a, b) => a[0] - b[0])
            const n = r() < 0.5 ? 2 : 3
            for (let k = 0; k < n; k++) {
                if (d[k][0] > 1.3) break
                const key = Math.min(i, d[k][1]) + "-" + Math.max(i, d[k][1])
                if (!seen[key]) { seen[key] = 1; ls.push([i, d[k][1], d[k][0]]) }
            }
        }
        stars = s; links = ls
        const pos = [], col = []
        for (const l of ls) {
            const k = 0.26 * (1.25 - l[2] / 1.15)
            pos.push(L.v3(s[l[0]].p), L.v3(s[l[1]].p)); col.push(L.ink(k), L.ink(k))
        }
        lines.positions = pos; lines.colors = col
        const dp = [], dc = []
        for (let i = 0; i < 900; i++) {
            const u = r() * 2 - 1, th = r() * 6.283, rad = 6 + r() * 6, q = Math.sqrt(1 - u * u)
            dp.push(Qt.vector3d(q * Math.cos(th) * rad, u * rad, q * Math.sin(th) * rad)); dc.push(L.ink(0.05 + Math.pow(r(), 4) * 0.25))
        }
        dust.positions = dp; dust.colors = dc
        const sp = []
        for (const st of s) sp.push(L.v3(st.p))
        points.positions = sp
    }
    Component.onCompleted: build()
    onClockChanged: {
        const col = []
        for (const st of stars) col.push(L.ink(st.b * (0.55 + 0.45 * Math.sin(st.tw + clock / st.per * 6.283))))
        points.colors = col
        if (clock - litAt > 4.5 && links.length) { lit = Math.floor(Math.random() * links.length); litAt = clock }
        const age = clock - litAt, k = Math.sin(Math.min(1, age / 3) * Math.PI) * 0.6
        if (lit >= 0) {
            const l = links[lit]
            talk.positions = [L.v3(stars[l[0]].p), L.v3(stars[l[1]].p)]
            talk.colors = [L.ink(k), L.ink(k)]
        }
    }

    View3D {
        anchors.fill: parent
        environment: SceneEnvironment {
            backgroundMode: SceneEnvironment.Color; clearColor: "black"
            antialiasingMode: SceneEnvironment.MSAA; antialiasingQuality: SceneEnvironment.High
        }
        PerspectiveCamera { position: Qt.vector3d(0, 1.3, 8.6); eulerRotation.x: -9; fieldOfView: 50; clipNear: 0.05 }
        Node {
            eulerRotation.y: scene.clock * 360 / 200; eulerRotation.x: 12
            Model { geometry: ProceduralMesh { id: lines; primitiveMode: ProceduralMesh.Lines } materials: ink }
            Model { geometry: ProceduralMesh { id: talk; primitiveMode: ProceduralMesh.Lines } materials: ink }
            Model { geometry: ProceduralMesh { id: points; primitiveMode: ProceduralMesh.Points } materials: PrincipledMaterial { lighting: PrincipledMaterial.NoLighting; vertexColorsEnabled: true; blendMode: PrincipledMaterial.Screen; pointSize: 3 } }
        }
        Node {
            eulerRotation.y: scene.clock * 360 / 320
            Model { geometry: ProceduralMesh { id: dust; primitiveMode: ProceduralMesh.Points } materials: PrincipledMaterial { lighting: PrincipledMaterial.NoLighting; vertexColorsEnabled: true; blendMode: PrincipledMaterial.Screen; pointSize: 1.5 } }
        }
    }
    PrincipledMaterial { id: ink; lighting: PrincipledMaterial.NoLighting; vertexColorsEnabled: true; blendMode: PrincipledMaterial.Screen }
}
