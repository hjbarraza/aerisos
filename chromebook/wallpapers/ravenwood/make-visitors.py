# Draws the first visitor files for ravenwood. Each frame is a grid of characters, one per dot.
import math, os, sys
OUT = os.path.expanduser("~/.config/aeris/ravenwood")
class C:
    def __init__(s, w, h): s.w, s.h = w, h; s.g = [[' '] * w for _ in range(h)]
    def put(s, x, y, ch='#'):
        x, y = int(round(x)), int(round(y))
        if 0 <= x < s.w and 0 <= y < s.h: s.g[y][x] = ch
    def ell(s, cx, cy, rx, ry, rot=0, ch='#'):
        c, sn = math.cos(rot), math.sin(rot); R = int(max(rx, ry)) + 2
        for y in range(int(cy) - R, int(cy) + R + 1):
            for x in range(int(cx) - R, int(cx) + R + 1):
                dx, dy = x - cx, y - cy; a = (dx * c + dy * sn) / rx; b = (-dx * sn + dy * c) / ry
                if a * a + b * b <= 1: s.put(x, y, ch)
    def line(s, x0, y0, x1, y1, w0=1.0, w1=None, ch='#'):
        w1 = w0 if w1 is None else w1; n = int(max(abs(x1 - x0), abs(y1 - y0)) * 2) + 1
        for i in range(n + 1):
            f = i / n; r = (w0 + (w1 - w0) * f) / 2; x, y = x0 + (x1 - x0) * f, y0 + (y1 - y0) * f
            if r <= 0.6: s.put(x, y, ch)
            else: s.ell(x, y, r, r, 0, ch)
    def poly(s, pts, ch='#'):
        ys = [p[1] for p in pts]
        for y in range(int(min(ys)), int(max(ys)) + 1):
            yc = y + 0.5; xs = []
            for i in range(len(pts)):
                (ax, ay), (bx, by) = pts[i], pts[(i + 1) % len(pts)]
                if (ay <= yc < by) or (by <= yc < ay): xs.append(ax + (yc - ay) / (by - ay) * (bx - ax))
            xs.sort()
            for i in range(0, len(xs) - 1, 2):
                for x in range(int(round(xs[i])), int(round(xs[i + 1]))): s.put(x, y, ch)
    def text(s): return "\n".join("".join(r).rstrip() or "." for r in s.g)
def write(name, keys, frames):
    with open(os.path.join(OUT, name + ".visitor"), "w") as f:
        f.write("# %s: a visitor for ravenwood. Edit freely; see the notes in ravenwood.c or copy this file to make another.\n" % name)
        for k, v in keys.items(): f.write("%s = %s\n" % (k, v))
        for fr in frames: f.write("frame\n" + fr.text() + "\n")
def leg(c, hx, hy, L, swing, w=1.8, back=False):
    # two-part leg from the hip; the knee bends when the leg is lifted forward
    lift = max(0, math.sin(swing)) ; a = 0.42 * math.cos(swing)
    kx, ky = hx + math.sin(a) * L * 0.5 + (-.8 if back else .6) * lift, hy + L * 0.5 - lift * 0.8
    fx, fy = kx + math.sin(a * 0.4) * L * 0.5 - (1.5 * lift if not back else -0.5 * lift), hy + L - lift * 2.6
    c.line(hx, hy, kx, ky, w, w * 0.8); c.line(kx, ky, fx, fy, w * 0.8, w * 0.6)

def deer(phase, pose="walk"):
    c = C(54, 46); g = 44
    for i, (hx, ph) in enumerate([(33.5, 0), (31.5, math.pi), (14.5, math.pi * 0.5), (16.5, math.pi * 1.5)]):
        leg(c, hx, 25, g - 25, phase + ph if pose == "walk" else math.pi * 1.5, 1.9, back=i >= 2)
    c.ell(24, 21, 13, 6.3); c.ell(34, 20.5, 5, 6.2); c.ell(13, 20, 5, 5.6)
    c.ell(9.5, 17.5, 1.8, 2.4, 0.5)                                   # tail
    if pose == "graze":
        c.line(37, 20, 44, 33, 5.2, 3.6); c.ell(46, 37, 2.6, 4.2, -0.5); c.line(44, 31, 42, 28, 1.6); c.line(45.5, 31.5, 46, 28, 1.6)
        hx, hy = 44, 30
    else:
        up = 2 if pose == "alert" else 0
        c.line(36, 18, 41, 8 - up, 5.4, 3.8); c.ell(44, 7 - up, 4.4, 2.7, 0.18)
        c.line(41, 5.5 - up, 38, 1.5 - up, 1.8, 1.0); c.line(42.5, 5 - up, 42, 0.5 - up, 1.8, 1.0)   # ears
        c.put(48.2, 7.6 - up)
    return c
def fox(phase, pose="trot"):
    c = C(46, 20); g = 19
    for i, (hx, ph) in enumerate([(28.5, 0), (27, math.pi), (13, math.pi * 0.6), (14.5, math.pi * 1.6)]):
        leg(c, hx, 11, g - 11, phase + ph if pose == "trot" else math.pi * 1.5, 1.5, back=i >= 2)
    c.ell(20, 9.5, 10, 3.4); c.ell(27.5, 9.2, 3.6, 3.8)
    c.poly([(11, 8), (6, 6.5), (1, 9.5), (0, 12.5), (4, 14), (9, 12), (12, 10.5)]); c.line(1, 10, 3, 13, 1.5, ch=':')   # brush
    hy = 10.5 if pose == "trot" else 6.5
    c.line(29, 8.5, 33.5, hy, 4, 3.4); c.ell(35, hy, 3.3, 2.5, 0.15); c.poly([(36, hy - 1.4), (41.5, hy + 1.2), (36, hy + 2.2)])
    c.poly([(32.5, hy - 1.5), (33, hy - 5.5), (35.2, hy - 2.2)]); c.poly([(34.8, hy - 2), (36, hy - 5.5), (37.4, hy - 1.6)])   # ears
    return c
def owl(phi):
    c = C(46, 34); cy = 17
    tip = (15 - 3 * math.cos(phi), cy - 15 * math.sin(phi))
    c.poly([(15, cy - 1), (27, cy - 1.5), (tip[0] + 8, tip[1] - 1 * math.sin(phi)), (tip[0] + 2, tip[1]), (tip[0] - 5, tip[1] + 2 + abs(math.cos(phi)) * 2), (11, cy + 2)])
    c.ell(21, cy, 8, 4.3); c.ell(30, cy - 0.5, 4.8, 4.6); c.poly([(13, cy - 2.5), (6, cy - 1.5), (6.5, cy + 2.5), (13, cy + 3)])
    c.put(32.5, cy - 1, '*')
    return c
def bat(up):
    c = C(11, 6)
    if up: [c.put(x, y) for x, y in [(0, 0), (1, 1), (2, 1), (3, 2), (4, 2), (5, 3), (5, 2), (6, 2), (7, 2), (8, 1), (9, 1), (10, 0), (2, 2), (8, 2), (4, 3), (6, 3)]]
    else:  [c.put(x, y) for x, y in [(0, 5), (1, 4), (2, 3), (3, 3), (4, 2), (5, 3), (5, 2), (6, 2), (7, 3), (8, 3), (9, 4), (10, 5), (3, 4), (7, 4), (2, 4), (8, 4)]]
    return c
def leafshape(k):
    c = C(4, 3)
    for x, y, ch in [[(1, 0, '#'), (2, 1, '#'), (0, 1, ':'), (1, 1, '#'), (2, 2, ':')], [(0, 1, '#'), (1, 1, '#'), (2, 1, '#'), (3, 1, ':'), (1, 0, ':')],
                     [(2, 0, '#'), (1, 1, '#'), (2, 1, '#'), (0, 2, ':'), (1, 2, '#')], [(1, 0, '#'), (1, 1, '#'), (1, 2, '#'), (2, 1, ':')]][k]: c.put(x, y, ch)
    return c
def star():
    c = C(30, 12)
    for i in range(28): c.put(i, i * 0.38, '*' if i > 9 else (':' if i % 2 else ' '))
    c.put(28, 10.3, '*'); c.put(28, 11.3, '*'); c.put(27, 11, '*')
    return c
def farraven(phi):
    c = C(24, 16); cy = 8
    c.ell(11, cy, 6, 1.9); c.ell(17.5, cy - 0.5, 2, 1.7); c.line(19, cy - 0.3, 22.5, cy + 0.3, 1.4, 0.6); c.poly([(6, cy - 1), (0.5, cy - 1.5), (0, cy + 1), (6, cy + 1.2)])
    c.poly([(8, cy), (15, cy), (10.5 - 2 * math.cos(phi), cy - 8 * math.sin(phi)), (6.5 - 2 * math.cos(phi), cy - 7 * math.sin(phi))])
    return c

write("deer", dict(layer=2, path="walk", speed=11, every=420, stops=2, stoptime=4.5, stopframes="4 5", frametime=0.2),
      [deer(i * math.pi / 2) for i in range(4)] + [deer(0, "alert"), deer(0, "graze")])
write("fox", dict(layer=3, path="walk", speed=34, every=520, stops=1, stoptime=2.2, stopframes="4", frametime=0.11),
      [fox(i * math.pi / 2) for i in range(4)] + [fox(0, "look")])
write("owl", dict(layer=3, path="fly", speed=62, every=480, height=0.30, bob=5, angle=2, frametime=0.13),
      [owl(a) for a in (1.0, 0.45, -0.5, -0.9, -0.3, 0.5)])
write("bats", dict(layer=2, tone=30, path="fly", speed=95, every=360, height=0.44, bob=11, count=3, frametime=0.07, scale=1.5), [bat(1), bat(0)])
write("leaves", dict(layer=3, path="fall", speed=22, every=260, count=11, frametime=0.28, scale=2, tone=14), [leafshape(k) for k in range(4)])
write("shooting-star", dict(layer=-1, path="fly", speed=420, every=700, height=0.20, angle=14, frametime=1), [star()])
write("far-raven", dict(layer=2, tone=34, path="fly", speed=48, every=380, height=0.36, bob=4, frametime=0.1), [farraven(a) for a in (1.0, 0.5, -0.4, -0.9, -0.3, 0.5)])
for n, c in [("deer walk", deer(0)), ("deer graze", deer(0, "graze")), ("fox", fox(1.0)), ("owl up", owl(1.0)), ("owl down", owl(-0.9))]:
    print("==", n); print(c.text())
