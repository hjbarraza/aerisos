.pragma library
// Shared helpers for the wallpaper scenes.

function rng(seed) {                       // mulberry32: small, fast, seedable
    let s = seed | 0
    return function () {
        s = (s + 0x6D2B79F5) | 0
        let t = Math.imul(s ^ (s >>> 15), 1 | s)
        t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t
        return ((t ^ (t >>> 14)) >>> 0) / 4294967296
    }
}
function norm(v) { const l = Math.hypot(v[0], v[1], v[2]) || 1; return [v[0] / l, v[1] / l, v[2] / l] }
function cross(a, b) { return [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]] }

// Warm white ink scaled by brightness k (0..1). Scenes draw with Screen blending on black, so
// a dimmer colour is a more transparent line.
const INK = [0.94, 0.93, 0.91]
function ink(k) { return Qt.vector4d(INK[0] * k, INK[1] * k, INK[2] * k, 1) }
function v3(p) { return Qt.vector3d(p[0], p[1], p[2]) }
