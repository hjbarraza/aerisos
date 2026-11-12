// Particles: thousands of faint points drifting slowly toward you, like snow at night or stars
// from a slow ship. Two copies of one block of space leapfrog, so the drift never ends. Points
// fade in from the far end and brighten as they come close.
import QtQuick
import QtQuick3D
import QtQuick3D.Helpers
import "lib.js" as L

Item {
    id: scene
    property real clock: 0
    readonly property real depth: 40
    readonly property real speed: 1.1          // units per second
    readonly property real off: (clock * speed) % depth

    function build() {
        const r = L.rng(Math.floor(Math.random() * 2147483647)), pos = [], col = []
        for (let i = 0; i < 7000; i++) {
            const z = -r() * depth, spread = 1.2 + (-z + 1) * 0.6   // wider with distance: fills the view cone
            pos.push(Qt.vector3d((r() - 0.5) * spread * 1.9, (r() - 0.5) * spread * 1.1, z))
            col.push(L.ink(0.3 + Math.pow(r(), 4) * 0.7))
        }
        a.positions = pos; a.colors = col; b.positions = pos; b.colors = col
    }
    Component.onCompleted: build()

    View3D {
        anchors.fill: parent
        environment: SceneEnvironment {
            backgroundMode: SceneEnvironment.Color; clearColor: "black"
        }
        PerspectiveCamera { position: Qt.vector3d(0, 0, 1); fieldOfView: 60; clipNear: 0.05; clipFar: 100 }
        Model {
            z: scene.off; eulerRotation.z: scene.clock * 0.6
            geometry: ProceduralMesh { id: a; primitiveMode: ProceduralMesh.Points }
            materials: pts
        }
        Model {
            z: scene.off - scene.depth; eulerRotation.z: scene.clock * 0.6
            geometry: ProceduralMesh { id: b; primitiveMode: ProceduralMesh.Points }
            materials: pts
        }
    }
    CustomMaterial {        // unlit ink that fades into black with distance (fade.vert/.frag); Fog skips unlit
        id: pts
        property real fadeNear: 4
        property real fadeFar: 38
        property real pointSize: 2
        property real nearBoost: 1.8
        shadingMode: CustomMaterial.Unshaded
        sourceBlend: CustomMaterial.One
        destinationBlend: CustomMaterial.OneMinusSrcColor
        cullMode: Material.NoCulling
        depthDrawMode: Material.NeverDepthDraw
        vertexShader: "fade.vert"
        fragmentShader: "fade.frag"
    }
}
