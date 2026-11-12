// Globe: a slowly turning wireframe Earth. Graticule every 15°, Natural Earth coastlines, and
// the real day/night: lines on the night side are dimmer, from the current subsolar point.
// A small light marks home (Valencia, as the orbit map).
import QtQuick
import QtQuick3D
import QtQuick3D.Helpers
import "lib.js" as L
import "land.js" as Land

Item {
    id: scene
    property real clock: 0
    readonly property real homeLat: 39.47
    readonly property real homeLon: -0.38
    property var verts: []          // unit vectors, in pairs (line segments)
    property var weights: []        // base brightness per vertex
    property real lastSun: -1000

    function xyz(lat, lon) {        // y up, lon 0 facing +z
        const la = lat * Math.PI / 180, lo = lon * Math.PI / 180
        return [Math.cos(la) * Math.sin(lo), Math.sin(la), Math.cos(la) * Math.cos(lo)]
    }
    function build() {
        const v = [], w = []
        function seg(a, b, k) { v.push(a, b); w.push(k, k) }
        for (let lat = -75; lat <= 75; lat += 15)             // parallels
            for (let lon = -180; lon < 180; lon += 3) seg(xyz(lat, lon), xyz(lat, lon + 3), lat === 0 ? 0.16 : 0.09)
        for (let lon = -180; lon < 180; lon += 15)            // meridians
            for (let lat = -90; lat < 90; lat += 3) seg(xyz(lat, lon), xyz(lat + 3, lon), 0.09)
        for (const ring of Land.rings)                         // coastlines
            for (let i = 1; i < ring.length; i++) seg(xyz(ring[i - 1][1], ring[i - 1][0]), xyz(ring[i][1], ring[i][0]), 0.42)
        verts = v; weights = w
        const pos = []
        for (const p of v) pos.push(L.v3(p))
        lines.positions = pos
        home.position = L.v3(xyz(homeLat, homeLon).map(c => c * 1.004))
        shade()
    }
    function sunVector() {          // subsolar point from the current UTC time
        const d = new Date(), day = (d - Date.UTC(d.getUTCFullYear(), 0, 0)) / 864e5
        const decl = -23.44 * Math.cos(2 * Math.PI / 365 * (day + 10))
        const hours = d.getUTCHours() + d.getUTCMinutes() / 60
        return xyz(decl, (12 - hours) * 15)
    }
    function shade() {              // day side bright, night side dim, soft terminator
        const s = sunVector(), col = []
        for (let i = 0; i < verts.length; i++) {
            const p = verts[i], dot = p[0] * s[0] + p[1] * s[1] + p[2] * s[2]
            const day = Math.min(1, Math.max(0, (dot + 0.12) / 0.24))
            col.push(L.ink(weights[i] * (0.28 + 0.72 * day)))
        }
        lines.colors = col
        lastSun = clock
    }
    Component.onCompleted: build()
    onClockChanged: if (clock - lastSun > 60) shade()

    View3D {
        anchors.fill: parent
        environment: SceneEnvironment {
            backgroundMode: SceneEnvironment.Color; clearColor: "black"
            antialiasingMode: SceneEnvironment.MSAA; antialiasingQuality: SceneEnvironment.High
        }
        PerspectiveCamera { position: Qt.vector3d(0, 0.55, 3.1); eulerRotation.x: -10; fieldOfView: 40; clipNear: 0.01 }
        Node {
            eulerRotation.z: 23.44 * 0.4
            Node {
                eulerRotation.y: scene.clock * 360 / 240     // one turn every four minutes
                Model { geometry: ProceduralMesh { id: lines; primitiveMode: ProceduralMesh.Lines } materials: inkLines }
                Model {
                    id: home
                    geometry: ProceduralMesh { primitiveMode: ProceduralMesh.Points; positions: [Qt.vector3d(0, 0, 0)]; colors: [L.ink(0.25 + 0.6 * Math.pow(Math.max(0, Math.sin(scene.clock * 1.6)), 6))] }
                    materials: PrincipledMaterial { lighting: PrincipledMaterial.NoLighting; vertexColorsEnabled: true; blendMode: PrincipledMaterial.Screen; pointSize: 4 }
                }
            }
        }
    }
    PrincipledMaterial { id: inkLines; lighting: PrincipledMaterial.NoLighting; vertexColorsEnabled: true; blendMode: PrincipledMaterial.Screen }
}
