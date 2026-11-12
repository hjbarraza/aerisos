// Terrain: a grey wireframe landscape gliding toward the horizon. The ground repeats every
// `tile` units along the flight path (its noise is periodic there), and two copies leapfrog,
// so the flight never ends. Far lines sink into black fog.
import QtQuick
import QtQuick3D
import QtQuick3D.Helpers
import "lib.js" as L

Item {
    id: scene
    property real clock: 0
    readonly property real tile: 48
    readonly property real width3d: 70
    readonly property real step: 1.2
    readonly property real speed: 2.2
    readonly property real off: (clock * speed) % tile

    function ground(x, z) {
        // sum of sines; z frequencies are whole cycles per tile, so the ground tiles seamlessly
        const w = 2 * Math.PI / tile, ax = Math.abs(x)
        let h = 0.9 * Math.sin(x * 0.19 + 1.3 * Math.sin(z * w * 2)) * Math.cos(z * w * 3)
              + 0.55 * Math.sin(x * 0.41 + z * w * 5 + 0.7) + 0.3 * Math.sin(x * 0.83 - z * w * 9)
              + 0.18 * Math.cos(x * 1.7 + z * w * 14)
        return h * (0.25 + Math.min(1, ax / 9) * 1.6)     // a flat valley to fly down, hills at the sides
    }
    function build() {
        const pos = [], col = [], nx = Math.round(width3d / step), nz = Math.round(tile / step)
        function p(i, j) { const x = -width3d / 2 + i * step, z = -j * step; return Qt.vector3d(x, ground(x, z), z) }
        function k(v) { return L.ink(0.2 + 0.08 * Math.max(0, v.y)) }
        for (let j = 0; j < nz; j++)
            for (let i = 0; i <= nx; i++) {
                const a = p(i, j)
                if (i < nx) { const b = p(i + 1, j); pos.push(a, b); col.push(k(a), k(b)) }
                const c = p(i, j + 1); pos.push(a, c); col.push(k(a), k(c))
            }
        g1.positions = pos; g1.colors = col; g2.positions = pos; g2.colors = col
    }
    Component.onCompleted: build()

    View3D {
        anchors.fill: parent
        environment: SceneEnvironment {
            backgroundMode: SceneEnvironment.Color; clearColor: "black"
            antialiasingMode: SceneEnvironment.MSAA; antialiasingQuality: SceneEnvironment.High
        }
        PerspectiveCamera {
            position: Qt.vector3d(Math.sin(scene.clock * 0.05) * 1.5, 3.0, 2)
            eulerRotation.x: -9; eulerRotation.z: Math.sin(scene.clock * 0.05) * -2
            fieldOfView: 55; clipNear: 0.1; clipFar: 200
        }
        Model { z: scene.off; geometry: ProceduralMesh { id: g1; primitiveMode: ProceduralMesh.Lines } materials: ink }
        Model { z: scene.off - scene.tile; geometry: ProceduralMesh { id: g2; primitiveMode: ProceduralMesh.Lines } materials: ink }
        Model { z: scene.off - 2 * scene.tile; geometry: g1; materials: ink }
    }
    CustomMaterial {        // unlit ink that fades into black with distance (fade.vert/.frag); Fog skips unlit
        id: ink
        property real fadeNear: 8
        property real fadeFar: 75
        property real pointSize: 1
        property real nearBoost: 1.0
        property real floorLevel: 0
        shadingMode: CustomMaterial.Unshaded
        sourceBlend: CustomMaterial.One
        destinationBlend: CustomMaterial.OneMinusSrcColor
        cullMode: Material.NoCulling
        depthDrawMode: Material.NeverDepthDraw
        vertexShader: "fade.vert"
        fragmentShader: "fade.frag"
    }
}
