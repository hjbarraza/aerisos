import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// The pet in bar mode (`aeris-pet where bar`): a small dragon or raven living in a strip of
// the top bar, drawn here instead of by the aeris-pet overlay. It paces, sits, pecks and
// sleeps once the session goes idle (IdleMonitor). Something in the AERIS alerts keeps it
// awake and pacing faster with a "!" when it stops. Left click: hop and say a line from
// the greetings file. Middle click: drop a crumb. Right click: the pet menu (onRightClick).
// Frames only run while it moves; sitting and sleeping repaint on a slow timer.
Item {
    id: lane
    property string kind: "dragon"
    property var onRightClick: null

    implicitWidth: 120
    implicitHeight: Theme.barHeight

    // ---- state
    property real px: width / 2      // feet x
    property int dir: 1              // 1 faces right
    property string mode: "sit"      // walk, sit, sleep, hop, peck
    property real target: px
    property real modeEnd: 0         // ms timestamp the current mode ends at (sit, hop, peck)
    property real t: 0               // seconds, drives gait and wobble
    property real hopStart: 0
    property bool blink: false
    property var crumbs: []          // x positions on the ground
    readonly property bool alert: Status.airHot.length > 0 || Status.labels.length > 0
    readonly property bool moving: mode === "walk" || mode === "hop" || mode === "peck"
    readonly property real ground: height - 3

    readonly property var greetFallback: ["caw", "still here", "don't mind me"]
    readonly property var feedLines: ["oh! crumbs.", "don't mind if i do", "a snack. the universe provides."]
    property var greetings: greetFallback

    function now() { return Date.now() }
    function rand(a, b) { return a + Math.random() * (b - a) }
    function pick(list) { return list[Math.floor(Math.random() * list.length)] }

    function setMode(m, seconds) {
        mode = m
        modeEnd = now() + (seconds ?? 0) * 1000
        canvas.requestPaint()
    }
    function walkTo(x) {
        target = Math.max(10, Math.min(width - 10, x))
        if (Math.abs(target - px) < 1) { decide(); return }
        dir = target > px ? 1 : -1
        setMode("walk")
    }
    // Pick the next thing to do once the current one is over.
    function decide() {
        if (crumbs.length > 0) {
            let best = crumbs[0]
            for (const c of crumbs) if (Math.abs(c - px) < Math.abs(best - px)) best = c
            if (Math.abs(best - px) < 3) { setMode("peck", 1.4); return }
            walkTo(best); return
        }
        if (idle.isIdle && !alert) { setMode("sleep"); return }
        const r = Math.random()
        if (r < (alert ? 0.75 : 0.45)) walkTo(rand(10, width - 10))
        else if (r < 0.9 || kind !== "raven") setMode("sit", alert ? rand(1, 3) : rand(4, 12))
        else setMode("peck", 1.2)
    }
    function hop() {
        hopStart = now()
        setMode("hop", 1.1)
    }
    function say(text) {
        bubbleText.text = text
        bubble.visible = true
        bubbleTimer.restart()
    }
    function eatCrumb() {
        const rest = crumbs.filter(c => Math.abs(c - px) >= 4)
        if (rest.length !== crumbs.length) { crumbs = rest; say(pick(feedLines)) }
    }

    // ---- clock
    FrameAnimation {
        running: lane.visible && lane.moving
        onTriggered: lane.step(Math.min(frameTime, 0.05))
    }
    function step(dt) {
        t += dt
        if (mode === "walk") {
            const speed = alert ? 30 : 15
            const d = target - px
            if (Math.abs(d) <= speed * dt) { px = target; decide() }
            else px += Math.sign(d) * speed * dt
        } else if (now() >= modeEnd) {
            if (mode === "peck") eatCrumb()
            decide()
        }
        canvas.requestPaint()
    }
    // Sitting and sleeping: blinks, zzz and the end of a rest. No frames needed for that.
    Timer {
        interval: 400
        running: lane.visible && !lane.moving
        repeat: true
        onTriggered: {
            lane.t += 0.4
            lane.blink = lane.mode === "sit" && Math.random() < 0.08
            if (lane.mode === "sit" && lane.now() >= lane.modeEnd) lane.decide()
            canvas.requestPaint()
        }
    }
    IdleMonitor {
        id: idle
        timeout: 300
        onIsIdleChanged: if (!isIdle && lane.mode === "sleep") { lane.say("i was not asleep"); lane.decide() }
    }
    onAlertChanged: if (alert && mode === "sleep") decide()
    onKindChanged: canvas.requestPaint()
    Component.onCompleted: decide()

    FileView {
        path: Quickshell.env("HOME") + "/.config/tinyraven/greetings.txt"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            const ls = text().split("\n").map(s => s.trim()).filter(s => s && !s.startsWith("#"))
            lane.greetings = ls.length ? ls : lane.greetFallback
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
        onClicked: ev => {
            if (ev.button === Qt.RightButton) { if (lane.onRightClick) lane.onRightClick(); return }
            if (ev.button === Qt.MiddleButton) {
                lane.crumbs = lane.crumbs.concat([Math.max(8, Math.min(lane.width - 8, ev.x + lane.rand(-6, 6)))])
                if (lane.mode !== "peck") lane.decide()
                canvas.requestPaint()
                return
            }
            if (Math.abs(ev.x - lane.px) < 14) { lane.hop(); lane.say(lane.pick(lane.greetings)) }
            else lane.walkTo(ev.x)
        }
    }

    // ---- speech bubble, hung under the bar above the pet
    PopupWindow {
        id: bubble
        anchor.item: lane
        anchor.rect.x: Math.round(lane.px - implicitWidth / 2)
        anchor.rect.y: lane.height + 2
        implicitWidth: Math.min(bubbleText.implicitWidth, 220) + 16
        implicitHeight: bubbleText.implicitHeight + 10
        visible: false
        color: "transparent"
        mask: Region {}   // never in the way of a click
        Rectangle {
            anchors.fill: parent
            color: Theme.bg
            border.color: Theme.line
            border.width: 1
            radius: 3
        }
        Text {
            id: bubbleText
            x: 8; y: 5
            width: Math.min(implicitWidth, 220)
            wrapMode: Text.Wrap
            color: Theme.fg
            font { family: Theme.sans; pixelSize: Theme.small }
        }
    }
    Timer { id: bubbleTimer; interval: 4500; onTriggered: bubble.visible = false }

    // ---- drawing
    Canvas {
        id: canvas
        anchors.fill: parent
        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            ctx.lineCap = "round"
            ctx.lineJoin = "round"
            // crumbs
            ctx.fillStyle = Theme.dim
            for (const c of lane.crumbs) ctx.fillRect(Math.round(c) - 1, lane.ground - 1.5, 2, 1.5)

            let lift = 0
            if (lane.mode === "hop") {
                const s = (lane.now() - lane.hopStart) / 1000
                lift = 6 * Math.abs(Math.sin(s * Math.PI * 2.7))
            } else if (lane.mode === "walk" && lane.kind === "raven") {
                lift = 1.6 * Math.abs(Math.sin(lane.t * 9))
            }
            ctx.save()
            ctx.translate(Math.round(lane.px * 2) / 2, lane.ground - lift)
            ctx.scale(lane.dir, 1)
            if (lane.kind === "raven") drawRaven(ctx, lift > 0.5)
            else drawDragon(ctx)
            ctx.restore()

            // marks above the head: zzz asleep, ! while an alert is up and it stands still
            ctx.fillStyle = Theme.dim
            ctx.font = "bold 8px '" + Theme.sans + "'"
            const hx = lane.px + lane.dir * 4
            if (lane.mode === "sleep") {
                const k = (lane.t * 0.6) % 1
                ctx.globalAlpha = 1 - k
                ctx.fillText("z", hx + lane.dir * (2 + 3 * k), lane.ground - 14 - 6 * k)
                ctx.globalAlpha = 1
            } else if (lane.alert && lane.mode === "sit") {
                ctx.fillStyle = Theme.fg
                ctx.fillText("!", hx, lane.ground - 16)
            }
        }

        function eye(ctx, x, y) {
            if (lane.mode === "sleep" || lane.blink) {
                ctx.strokeStyle = Theme.bg
                ctx.lineWidth = 0.8
                ctx.beginPath(); ctx.moveTo(x - 0.9, y); ctx.lineTo(x + 0.9, y); ctx.stroke()
            } else {
                ctx.fillStyle = Theme.bg
                ctx.beginPath(); ctx.arc(x, y, 0.85, 0, Math.PI * 2); ctx.fill()
            }
        }

        // Raven, feet at (0, 0), facing +x, about 16 px wide and 13 px tall.
        function drawRaven(ctx, airborne) {
            const sleeping = lane.mode === "sleep"
            const peck = lane.mode === "peck" ? 0.5 + 0.2 * Math.sin(lane.t * 18) : 0
            const flap = lane.mode === "hop" ? 0.7 * Math.sin(lane.t * 30) - 0.3 : 0
            ctx.save()
            if (sleeping) ctx.translate(0, 1.5)          // hunkers down
            // legs
            ctx.strokeStyle = Theme.dim
            ctx.lineWidth = 0.9
            ctx.beginPath()
            for (const lx of [-1.2, 1.0]) {
                const fx = airborne ? lx - 1.2 : lx
                ctx.moveTo(lx, -3); ctx.lineTo(fx, sleeping ? -1.5 : 0)
                ctx.moveTo(fx, sleeping ? -1.5 : 0); ctx.lineTo(fx + 1.6, sleeping ? -1.5 : 0)
            }
            ctx.stroke()
            ctx.rotate(peck)
            // tail
            ctx.fillStyle = Theme.dim
            ctx.beginPath(); ctx.moveTo(-3.5, -7.2); ctx.lineTo(-9, -5.2); ctx.lineTo(-8.5, -4); ctx.lineTo(-3, -4.6); ctx.fill()
            // body
            ctx.fillStyle = Theme.fg
            ctx.strokeStyle = Theme.dim
            ctx.lineWidth = 0.7
            ctx.beginPath(); ctx.ellipse(-5.5, -9.6, 10, 6.8); ctx.fill(); ctx.stroke()
            // head and beak
            ctx.beginPath(); ctx.arc(3.6, -10.2, 3, 0, Math.PI * 2); ctx.fill(); ctx.stroke()
            ctx.fillStyle = Theme.dim
            ctx.beginPath(); ctx.moveTo(6.2, -11.3); ctx.lineTo(9.6, -9.9); ctx.lineTo(6.2, -9.0); ctx.fill()
            // wing
            ctx.save()
            ctx.translate(-1.5, -8.6)
            ctx.rotate(flap)
            ctx.fillStyle = Qt.darker(Theme.fg, 1.25)
            ctx.beginPath(); ctx.ellipse(-4.5, -1.6, 7, 3.4); ctx.fill(); ctx.stroke()
            ctx.restore()
            eye(ctx, 4.4, -10.8)
            ctx.restore()
        }

        // Dragon, feet at (0, 0), facing +x: a short undulating body of tapering discs,
        // four stubby legs that step while it walks, horns and a back fin.
        function drawDragon(ctx) {
            const walking = lane.mode === "walk"
            const sleeping = lane.mode === "sleep"
            const wave = sleeping ? 0.3 : (walking || lane.mode === "hop" ? 1.4 : 0.6)
            const ph = lane.t * (walking ? 8 : 2)
            const pts = []
            for (let i = 0; i < 9; i++) {
                const y = (sleeping ? -3.2 : -6.0) + wave * Math.sin(ph - i * 0.8) * Math.min(1, i / 2)
                pts.push([4 - i * 2.1, y, 3.1 - i * 0.26])
            }
            // legs under discs 1 and 5
            ctx.strokeStyle = Theme.dim
            ctx.lineWidth = 1.1
            if (!sleeping) {
                ctx.beginPath()
                for (const [k, off] of [[1, 0], [5, Math.PI]]) {
                    const p = pts[k]
                    const sw = walking ? 1.4 * Math.sin(lane.t * 10 + off) : 0
                    ctx.moveTo(p[0] + 0.6, p[1]); ctx.lineTo(p[0] + 0.6 + sw, 0)
                    ctx.moveTo(p[0] - 0.6, p[1]); ctx.lineTo(p[0] - 0.6 - sw, 0)
                }
                ctx.stroke()
            }
            // back fins
            ctx.fillStyle = Qt.darker(Theme.fg, 1.25)
            for (const k of [2, 4, 6]) {
                const p = pts[k]
                ctx.beginPath()
                ctx.moveTo(p[0] + 1.2, p[1] - p[2] + 0.4)
                ctx.lineTo(p[0] - 0.4, p[1] - p[2] - 2.0)
                ctx.lineTo(p[0] - 1.4, p[1] - p[2] + 0.4)
                ctx.fill()
            }
            // body: one tapering tube along the spine, outline pass then fill pass
            for (const [col, pad] of [[Theme.dim, 1.2], [Theme.fg, 0]]) {
                ctx.strokeStyle = col
                for (let i = 0; i < pts.length - 1; i++) {
                    const a = pts[i], b = pts[i + 1]
                    ctx.lineWidth = (a[2] + b[2]) + pad
                    ctx.beginPath(); ctx.moveTo(a[0], a[1]); ctx.lineTo(b[0], b[1]); ctx.stroke()
                }
            }
            // head: skull, snout, horns
            const h = pts[0]
            const hx = h[0] + 2.8, hy = h[1] - 2.2
            ctx.strokeStyle = Theme.dim
            ctx.lineWidth = 0.9
            ctx.beginPath()
            ctx.moveTo(hx - 1.2, hy - 2.0); ctx.lineTo(hx - 3.6, hy - 4.6)
            ctx.moveTo(hx - 0.2, hy - 2.4); ctx.lineTo(hx - 1.8, hy - 5.2)
            ctx.stroke()
            ctx.fillStyle = Theme.fg
            ctx.lineWidth = 0.6
            ctx.beginPath(); ctx.ellipse(hx - 3.0, hy - 2.7, 6.0, 5.2); ctx.fill(); ctx.stroke()
            ctx.beginPath(); ctx.ellipse(hx + 0.8, hy - 1.4, 4.2, 3.0); ctx.fill(); ctx.stroke()
            ctx.beginPath(); ctx.ellipse(hx - 2.6, hy - 2.3, 5.2, 4.4); ctx.fill()
            eye(ctx, hx + 0.2, hy - 0.6)
        }
    }
}
