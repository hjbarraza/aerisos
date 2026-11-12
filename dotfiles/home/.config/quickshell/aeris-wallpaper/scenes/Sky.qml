// Sky: soft clouds drifting past at several depths, a quiet backdrop for the desktop pet.
// Every few minutes a distant dragon swims across the sky, small and pale, then is gone.
import QtQuick
import QtQuick3D
import "lib.js" as L

Item {
    id: scene
    property real clock: 0
    property var puffs: []
    readonly property real span: 90           // clouds wrap around this width (world units)

    function build() {
        const r = L.rng(Math.floor(Math.random() * 2147483647)), p = []
        for (let c = 0; c < 22; c++) {           // a cloud is a cluster of overlapping puffs
            const z = -8 - r() * 50, x = (r() - 0.5) * span, y = -3 + r() * 13 + (-z) * 0.08
            const size = 3 + r() * 4, n = 5 + Math.floor(r() * 6)
            for (let i = 0; i < n; i++)
                p.push({ x: x + (r() - 0.5) * size * 2.2, y: y + (r() - 0.5) * size * 0.45, z: z + (r() - 0.5) * 1.5,
                         s: size * (0.5 + r() * 0.7) / 100, a: 0.025 + r() * 0.05, v: 0.35 + 6 / -z })
        }
        p.sort((a, b) => a.z - b.z)              // far first, so blending stacks correctly
        puffs = p
    }
    Component.onCompleted: build()

    Canvas {                                     // one soft round puff, used as the cloud texture
        id: puffImage
        width: 128; height: 128; visible: false
        onPaint: {
            const ctx = getContext("2d"), g = ctx.createRadialGradient(64, 64, 0, 64, 64, 64)
            g.addColorStop(0, "rgba(255,255,255,1)"); g.addColorStop(0.45, "rgba(255,255,255,0.55)"); g.addColorStop(1, "rgba(255,255,255,0)")
            ctx.fillStyle = g; ctx.fillRect(0, 0, 128, 128)
        }
    }

    View3D {
        anchors.fill: parent
        environment: SceneEnvironment { backgroundMode: SceneEnvironment.Color; clearColor: "black" }
        PerspectiveCamera { position: Qt.vector3d(0, 2, 6); fieldOfView: 55; clipNear: 0.1; clipFar: 200 }
        Repeater3D {
            model: scene.puffs.length
            Model {
                required property int index
                readonly property var p: scene.puffs[index]
                source: "#Rectangle"
                position: Qt.vector3d(((p.x + scene.clock * p.v + scene.span * 10) % scene.span) - scene.span / 2, p.y, p.z)
                scale: Qt.vector3d(p.s * 2.2, p.s, 1)
                materials: PrincipledMaterial {
                    lighting: PrincipledMaterial.NoLighting
                    baseColor: Qt.rgba(0.88, 0.88, 0.9, 1)
                    baseColorMap: Texture { sourceItem: puffImage }
                    alphaMode: PrincipledMaterial.Blend
                    opacity: p.a
                    depthDrawMode: Material.NeverDepthDraw
                }
            }
        }
    }

    // The distant dragon: a pale serpentine silhouette crossing the upper sky now and then.
    Canvas {
        id: dragon
        anchors.fill: parent
        readonly property real every: 150      // seconds between crossings
        readonly property real dur: 45
        readonly property real age: scene.clock % every
        readonly property bool flying: age < dur && scene.clock > 20
        property int lastSeen: -1
        visible: flying
        onAgeChanged: if (flying || lastSeen !== 0) { lastSeen = flying ? 1 : 0; requestPaint() }
        onPaint: {
            const ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            if (!flying) return
            const cycle = Math.floor(scene.clock / every), dir = cycle % 2 ? -1 : 1
            const u = age / dur, hx = dir > 0 ? -80 + u * (width + 160) : width + 80 - u * (width + 160)
            const hy = height * (0.16 + 0.08 * ((cycle * 0.618) % 1)) + Math.sin(u * 9) * 14
            const fade = Math.min(1, u * 8, (1 - u) * 8)
            for (let i = 15; i >= 0; i--) {    // head first; the body follows in a travelling wave
                const s = i / 15, x = hx - dir * i * 7, y = hy + Math.sin(scene.clock * 3 - s * 5.5) * 6 * (0.2 + s)
                ctx.fillStyle = "rgba(230,230,232," + (0.22 * fade) + ")"
                ctx.beginPath(); ctx.arc(x, y, 4.2 * (1 - 0.7 * s), 0, 2 * Math.PI); ctx.fill()
            }
        }
    }
}
