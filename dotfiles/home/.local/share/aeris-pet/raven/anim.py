"""crowpet v4 animation: the polish pass on the v3 corvid rig.

v3 chose WHAT the crow does (sourced corvid behavior, see README). v4 is about
HOW it moves, so it reads as a live, cute pet instead of a posed sprite:

- Planted feet. Legs are solved with two-bone IK from the hips (which ride the
  body) down to feet that stay put on the ground. Any body motion - breathing,
  a bow, a crouch, a landing - bends the legs for free, and nothing skates.
- Procedural stepping. Walking moves each foot as its own little state
  machine: planted feet stay fixed in the world while the body travels, the
  trailing foot swings ahead every step length, and when the bird stops the
  feet gather back under it. Starts and stops are clean at any speed.
- One Animator owns time, crossfades, springs, blinking, breathing, saccades
  and the scheduler, so the live pet and the headless previews are the same
  motion.
- Follow-through: springs on tail, wing, head and body squash give overshoot
  and settle; breathing never stops and speeds up after exertion.

All angles in degrees, translations in viewBox units (scaled at draw time).
Sign conventions (screen coords, y down, bird faces +x):
  thigh +  = foot swings backward; shin - = knee folds (heel up); toes - = point down
  wing  +  = wing raised/spread up;  wing - = swept down across the belly
  tail  +  = tail tip down;  beak + = open;  rot + = nose-down pitch
  head_rot + = beak tips down (the head swings about the neck base)
  dy +     = body lower (the legs fold by themselves)
"""
import math
import random
from dataclasses import dataclass, field

TAU = 2 * math.pi

# ---- rig geometry (viewBox units), shared with the renderer -----------------
HIP_N, KNEE_N, ANKLE_N = (8.9, 11.0), (2.2, 29.9), (11.3, 58.5)
HIP_F, KNEE_F, ANKLE_F = (-1.3, 11.0), (-8.0, 29.9), (1.1, 58.5)
BODY_PIVOT = (0.0, 28.0)             # low pivot: pitch reads as weight over feet
L1 = math.dist(HIP_N, KNEE_N)        # both legs share bone lengths
L2 = math.dist(KNEE_N, ANKLE_N)
REST_TH = math.degrees(math.atan2(KNEE_N[1] - HIP_N[1], KNEE_N[0] - HIP_N[0]))
REST_SH = math.degrees(math.atan2(ANKLE_N[1] - KNEE_N[1], ANKLE_N[0] - KNEE_N[0]))
STAND = 1.6                          # resting knee bend, so legs can also extend


def clamp(x, lo=0.0, hi=1.0):
    return max(lo, min(hi, x))


def smooth(x):
    x = clamp(x)
    return x * x * (3 - 2 * x)


def bump(x):
    """0 -> 1 -> 0 over x in [0,1], zero outside."""
    return math.sin(math.pi * clamp(x))


def rot2(x, y, deg):
    c, s = math.cos(math.radians(deg)), math.sin(math.radians(deg))
    return x * c - y * s, x * s + y * c


def wrap(deg):
    return (deg + 180.0) % 360.0 - 180.0


@dataclass
class Leg:
    # authored, airborne: joint angles (used as lock -> 0)
    thigh: float = 0.0
    shin: float = 0.0
    toes: float = 0.0
    # authored, grounded: foot offset from its planted spot, and toe pitch
    fx: float = 0.0
    fy: float = 0.0
    toe: float = 0.0
    # solved: hip offset from rest (the hip rides the body)
    hx: float = 0.0
    hy: float = 0.0


POSE_FIELDS = ('dx', 'dy', 'rot', 'sx', 'sy', 'beak', 'blink', 'wing',
               'wing_spread', 'wing_w', 'tail', 'head_dx', 'head_dy',
               'head_rot', 'lock', 'vx')
LEG_FIELDS = ('thigh', 'shin', 'toes', 'fx', 'fy', 'toe')


@dataclass
class Pose:
    dx: float = 0.0
    dy: float = 0.0
    rot: float = 0.0
    sx: float = 1.0
    sy: float = 1.0
    beak: float = 0.0
    blink: float = 0.0
    wing: float = 0.0
    wing_spread: float = 1.0          # wing length scale
    wing_w: float = 1.0               # wing width scale (opens the folded wing)
    tail: float = 0.0
    head_dx: float = 0.0
    head_dy: float = 0.0
    head_rot: float = 0.0
    lock: float = 1.0                 # 1 = feet stick to the ground, 0 = airborne
    vx: float = 0.0                   # forward travel, units/s (window motion)
    near: Leg = field(default_factory=Leg)
    far: Leg = field(default_factory=Leg)

    def mix(self, other, a):
        """New pose: self blended toward other by a (0..1)."""
        out = Pose()
        for f_ in POSE_FIELDS:
            setattr(out, f_, getattr(self, f_) * (1 - a) + getattr(other, f_) * a)
        for leg in ('near', 'far'):
            s, o, d = getattr(self, leg), getattr(other, leg), getattr(out, leg)
            for f_ in LEG_FIELDS:
                setattr(d, f_, getattr(s, f_) * (1 - a) + getattr(o, f_) * a)
        return out


DURATIONS = {
    'idle': 3.4, 'walk': 8.0, 'flap': 1.2, 'jitter': 0.7,
    'caw': 0.7, 'hop': 0.66, 'dance': 2.4, 'fly': 2.6,
    'preen': 2.6, 'rouse': 1.1, 'flick': 0.9, 'held': math.inf,
    'flight': math.inf, 'peck': math.inf, 'sleep': math.inf,
}                                     # walk ends by distance; 8 s is only a cap.
# held, flight, peck and sleep last until the host starts something else: they
# are for a host that owns the bird's place and state (aeris-pet), not the
# scheduler.
WEIGHTS = {'idle': 5, 'walk': 2, 'flap': 1, 'jitter': 1, 'caw': 2, 'hop': 1,
           'dance': 1, 'fly': 2, 'preen': 2, 'rouse': 1, 'flick': 1}
CHAINS = {'caw': 2, 'hop': 2}         # up to this many extra repeats in a row
EXERTION = {'fly': 1.0, 'flight': 1.0, 'flap': 0.6, 'dance': 0.6, 'hop': 0.35, 'held': 0.5}

STEP = 15.0               # units travelled per step (two steps per stride)
WALK_V = 33.0             # units/s: ~0.9 s stride, duty factor ~0.62 (sourced)
SWING_T = 0.34            # seconds a foot spends in the air per step
HEAD_BOB_AMP = 3.0        # head thrust amplitude (artistic scale)
WINGBEAT_T = 0.45         # ~2.2 Hz: slow, deliberate large-corvid wingbeat
HOP_DIST = 16.0           # forward travel of one hop
TUCK = (52.0, -92.0, -18.0)   # legs folded under the body in flight


def head_bob(u):
    """Hold + thrust, u in [0,1). +1 fully thrust forward, -1 fully behind.
    Hold: head world-locked while the body advances under it; thrust: one
    ballistic snap forward (sourced, see README)."""
    HOLD = 0.72
    if u < HOLD:
        return 1.0 - 2.0 * (u / HOLD)
    return -1.0 + 2.0 * smooth((u - HOLD) / (1 - HOLD))


def _legs(p, thigh, shin, toes, far=0.9):
    p.near.thigh, p.near.shin, p.near.toes = thigh, shin, toes
    p.far.thigh, p.far.shin, p.far.toes = thigh * far, shin * far, toes * far


def pose_for(behavior, t, gait=(0.0, 0.0, 1)):
    """Authored pose at time t. gait = (step phase, speed 0..1, side) for walk."""
    p = Pose()
    if behavior == 'idle':
        # weight drifts from hip to hip on two slow, unrelated rhythms
        sway = math.sin(TAU * t / 5.3)
        s2 = math.sin(TAU * t / 3.1 + 1.0)
        p.dx = 1.3 * sway
        p.rot = 0.9 * sway + 0.4 * s2
        p.dy = 0.5 * sway * sway
        p.head_rot = -0.8 * sway
        p.tail = 1.5 * s2
    elif behavior == 'walk':
        ph, a, side = gait
        # vaulting walk: highest over the support leg at mid-stance, lowest at
        # double support (sourced); the feet themselves belong to the Stepper
        p.dy = a * (0.9 - 0.9 * math.cos(TAU * (ph - 0.38)))
        waddle = side * math.sin(math.pi * ph)
        p.rot = a * (2.0 + 0.8 * math.sin(TAU * ph) + 0.9 * waddle)
        p.tail = -a * 2.4 * waddle
        p.head_dx = a * HEAD_BOB_AMP * head_bob((ph + 0.3) % 1.0)
        p.head_rot = -p.rot * 0.8        # head holds level against body pitch
    elif behavior == 'hop':
        # two-footed and synchronous (sourced). Anticipate, stretch, tuck, absorb.
        T = DURATIONS['hop']
        C, L, A = 0.16, 0.24, 0.54       # crouched, toe-off, touchdown
        if t < C:
            e = smooth(t / C)
            p.dy = 7 * e
            p.sy = 1 - 0.06 * e; p.sx = 1 + 0.05 * e
            p.rot = 4 * e; p.tail = -7 * e
        elif t < L:
            e = smooth((t - C) / (L - C))
            p.dy = 7 - 10 * e
            p.sy = 0.94 + 0.13 * e; p.sx = 1.05 - 0.09 * e
            p.rot = 4 - 9 * e; p.tail = -7 + 7 * e
        elif t < A:
            v = (t - L) / (A - L)
            arc = 4 * v * (1 - v)
            p.lock = max(0.0, 1 - v / 0.1) + smooth((v - 0.9) / 0.1)
            p.dy = -3 - 14 * arc
            tuck = bump(v * 1.15)
            _legs(p, 30 * tuck, -72 * tuck, -18 * tuck)
            p.rot = -5 + 8 * v
            p.wing = 16 * arc; p.wing_w = 1 + 0.12 * arc   # tiny balance flutter
            p.sy = 1.07 - 0.07 * v; p.sx = 0.96 + 0.04 * v
            p.tail = 10 * arc
            p.vx = HOP_DIST / (A - L)
        else:
            w = (t - A) / (T - A)
            ab = bump(smooth(w))
            p.dy = -3 * (1 - smooth(w * 3)) + 5.5 * ab
            p.sy = 1 - 0.08 * ab; p.sx = 1 + 0.06 * ab
            p.rot = 3 * (1 - w)
        p.head_rot = -p.rot * 0.75       # head holds level
    elif behavior == 'flap':
        T = DURATIONS['flap']
        env = smooth(t / 0.15) * (1 - smooth((t - T + 0.2) / 0.2))
        th = TAU * 3 * t / T
        beat = math.sin(th)
        down = max(0.0, -math.cos(th)); up = max(0.0, math.cos(th))
        p.wing = env * (14 + 40 * beat)
        # full spread on the downstroke, adduct (fold) on the upstroke (sourced)
        p.wing_spread = 1.0 + env * (0.17 * down - 0.09 * up)
        p.wing_w = 1.0 + 0.3 * env
        p.dy = env * (-1.2 - 2.4 * down)  # up on its toes with each downstroke
        p.rot = env * (-3 - 1.5 * beat)   # chest up
        p.head_rot = -p.rot * 0.8
        p.tail = env * 6 * beat
    elif behavior == 'fly':
        T = DURATIONS['fly']
        TO, LD = 0.5, 0.55
        if t < TO:
            # leg-driven takeoff (sourced): countermovement crouch, wing raised
            # during the push, first downstroke at toe-off
            u = t / TO
            cr = bump(u / 0.7)
            e = smooth((u - 0.5) / 0.5)
            up = smooth(u / 0.6)
            p.dy = 9 * cr * (1 - e) - 8.6 * e
            p.rot = 8 * bump(u / 0.6) * (1 - e) - 8 * e
            p.wing = 62 * up - 46 * e
            p.wing_spread = 1 + 0.02 * up
            p.wing_w = 1 + 0.3 * up
            p.lock = 1 - smooth((u - 0.55) / 0.15)
            tuck = smooth((u - 0.6) / 0.4)
            _legs(p, TUCK[0] * tuck, TUCK[1] * tuck, TUCK[2] * tuck)
            p.tail = 6 * cr - 6 * e
        elif t < T - LD:
            th = TAU * (t - TO) / WINGBEAT_T
            beat = math.sin(th)
            down = max(0.0, -math.cos(th)); up = max(0.0, math.cos(th))
            p.wing = 16 + 40 * beat
            p.wing_spread = 1.02 + 0.16 * down - 0.10 * up   # upstroke adduction
            p.wing_w = 1.3
            _legs(p, *TUCK)
            p.rot = -8 + 1.5 * beat
            p.dy = -7 + 2.6 * beat           # dips between downstrokes
            p.tail = -6 + 3 * beat
            p.lock = 0.0
        else:
            # landing flare (sourced): pitch nose-UP, tail fanned down, wings
            # wide and braking, feet reach forward; the ground clamp in
            # solve_legs plants them, then the legs absorb
            v = (t - (T - LD)) / LD
            e = smooth(v)
            flare = bump(v / 0.8)
            p.rot = -8 * (1 - e) - 15 * flare
            p.dy = -7 * (1 - e) + 5 * bump((v - 0.7) / 0.3)
            p.wing = 16 * (1 - e) + 42 * flare + 7 * flare * math.sin(TAU * 6 * t)
            p.wing_spread = 1.02 + 0.16 * flare - 0.02 * e
            p.wing_w = 1.3 - 0.3 * smooth((v - 0.6) / 0.4)
            p.tail = -6 * (1 - e) + 20 * flare
            reach = smooth(v / 0.6)
            _legs(p, TUCK[0] + (-20 - TUCK[0]) * reach,
                  TUCK[1] + (-8 - TUCK[1]) * reach,
                  TUCK[2] + (10 - TUCK[2]) * reach)
            p.lock = smooth((v - 0.68) / 0.12)
        p.head_rot = -p.rot * 0.75           # head level
    elif behavior == 'caw':
        # cawing display (sourced): whole-body bow with the head lowered in
        # sync with the call, tail fanned, belly feathers raised, nictitating
        # membrane drawn. Breath in first, recoil after. Chained 1-3 times.
        up = smooth(t / 0.10) * (1 - smooth((t - 0.50) / 0.20))
        k = smooth((t - 0.10) / 0.07) * (1 - smooth((t - 0.42) / 0.22))
        p.dy = -1.6 * up + 2.8 * k
        p.rot = -4 * up + 9 * k
        p.head_rot = -8 * up + 13 * k
        p.head_dx = 3 * k                    # neck reaches into the call
        p.beak = 34 * k
        p.tail = 12 * k
        p.sx = 1 + 0.02 * up + 0.03 * k
        p.sy = 1 - 0.015 * k
        p.wing = -5 * k
        p.wing_spread = 1 + 0.04 * k
        p.blink = 0.85 * k
    elif behavior == 'flick':
        # wing-tail flicking (sourced): folded wings flick out, tail fans,
        # 1-3 quick pulses, typical just after landing
        f = max(bump(t / 0.28) ** 2, bump((t - 0.40) / 0.28) ** 2)
        p.wing = 17 * f
        p.wing_spread = 1 + 0.10 * f
        p.tail = -13 * f
        p.rot = -2.5 * f
        p.head_rot = -4 * f
        p.dy = -1.2 * f
    elif behavior == 'preen':
        # head swings down to the breast, beak nibbles along the feathers
        # (sourced mechanics); eyes half shut, wing eased out of the way
        u = t / DURATIONS['preen']
        e = smooth(u / 0.22) * (1 - smooth((u - 0.78) / 0.22))
        stroke = math.sin(TAU * 1.5 * t)
        p.head_rot = e * (31 + 5 * stroke)
        p.head_dx = 1.0 * e
        p.head_dy = e * (2.0 + 1.2 * stroke)
        p.rot = 5 * e
        p.dy = 1.2 * e
        p.tail = 4 * e
        p.wing = 7 * e
        p.beak = 8 * e * max(0.0, math.sin(TAU * 3.2 * t))
        p.blink = 0.55 * e
    elif behavior == 'rouse':
        # rousing (sourced): feathers raised, then a rapid shake-out with the
        # eyes shut, then a slow deflate
        if t < 0.28:
            e = smooth(t / 0.28)
            p.sx = 1 + 0.08 * e; p.sy = 1 + 0.05 * e
            p.dy = -1.6 * e
            p.wing = 7 * e
            p.tail = -6 * e
            p.head_rot = -6 * e
            p.blink = e
        elif t < 0.66:
            v = (t - 0.28) / 0.38
            damp = 1 - v
            sh = math.sin(TAU * 9.5 * (t - 0.28))
            p.dx = 2.1 * sh * damp
            p.rot = 3.2 * sh * damp
            p.head_rot = -6 * damp - 4 * sh * damp
            p.sx = 1.08 - 0.035 * v
            p.sy = 1.05 - 0.025 * v
            p.dy = -1.6 + 1.0 * v
            p.wing = 7 * damp + 4 * sh * damp
            p.tail = -6 * damp + 8 * sh * damp
            p.blink = 1.0
        else:
            e = smooth((t - 0.66) / 0.44)
            p.sx = 1.0 + 0.045 * (1 - e)
            p.sy = 1.0 + 0.025 * (1 - e)
            p.dy = -0.6 * (1 - e)
            p.blink = 1 - smooth((t - 0.66) / 0.15)
    elif behavior == 'jitter':
        f1, f2 = 39.0, 57.0
        p.dx = 1.7 * math.sin(f1 * t + 0.7) + 0.7 * math.sin(f2 * t)
        p.dy = 1.0 + 1.3 * math.sin(f2 * t + 2.1) + 0.5 * math.sin(f1 * t + 4.0)
        p.rot = 2.0 * math.sin(45 * t + 1.3)
        p.wing = 4 + 5 * math.sin(48 * t)
    elif behavior == 'dance':
        T = DURATIONS['dance']
        half = T / 2
        lift = bump((t / half) % 1.0)         # two side-steps
        side = 1 if (t // half) % 2 == 0 else -1
        up, down = (p.near, p.far) if side > 0 else (p.far, p.near)
        up.fy = -8 * lift; up.fx = -2 * lift; up.toe = -22 * lift
        p.dx = 2.6 * side * lift
        p.rot = 4.5 * side * lift
        beat = math.sin(TAU * 4 * t / T)
        p.dy = 2.4 * abs(math.sin(TAU * 2 * t / T))   # bounce into the knees
        p.tail = 9 * math.sin(TAU * 2 * t / T + 0.9)
        p.wing = 8 + 9 * beat
        p.beak = 7 * max(0.0, math.sin(TAU * t / T))
        p.head_rot = 6 * beat - p.rot * 0.5   # nods on the beat
        p.head_dx = -p.dx * 0.45
    elif behavior == 'held':
        # picked up: legs dangle, wings flutter for balance, beak open
        p.lock = 0.0
        sw = math.sin(2.6 * t)
        p.rot = 5 * sw
        p.dy = -9                        # lifted clear of the ground
        _legs(p, 10 + 5 * sw, -16 + 6 * math.sin(3.4 * t), 24, far=0.75)
        p.wing = 20 + 12 * math.sin(TAU * 5 * t)
        p.wing_w = 1.18
        p.tail = 6 - 4 * sw
        p.head_rot = -5 - p.rot * 0.7
        p.beak = 7
    elif behavior == 'flight':
        # the cruise of 'fly' on its own, for a host that flies the bird itself
        th = TAU * t / WINGBEAT_T
        beat = math.sin(th)
        down = max(0.0, -math.cos(th)); up = max(0.0, math.cos(th))
        p.wing = 16 + 40 * beat
        p.wing_spread = 1.02 + 0.16 * down - 0.10 * up
        p.wing_w = 1.3
        _legs(p, *TUCK)
        p.rot = -8 + 1.5 * beat
        p.dy = 2.6 * beat
        p.tail = -6 + 3 * beat
        p.head_rot = -p.rot * 0.75
        p.lock = 0.0
    elif behavior == 'peck':
        # tip forward over the feet, reach down, and strike a few times a second
        e = smooth(t / 0.25)
        strike = max(0.0, math.sin(TAU * 2.6 * t)) ** 2
        p.rot = e * (17 + 5 * strike)
        p.dy = e * (3 + 1.5 * strike)
        p.head_rot = e * (26 + 16 * strike)
        p.head_dx = e * 3 * strike
        p.tail = -8 * e                       # tail up as a counterweight
        p.beak = e * 7 * (1 - strike)
    elif behavior == 'sleep':
        # sat down on its feet, fluffed up, head sunk into the shoulders
        e = smooth(t / 0.8)
        p.dy = 13 * e
        p.sx = 1 + 0.05 * e; p.sy = 1 + 0.03 * e
        p.rot = -3 * e
        p.head_rot = 9 * e
        p.head_dx = -5 * e; p.head_dy = 4 * e
        p.tail = 5 * e
        p.blink = e
    p.dy += STAND
    return p


# ---- legs: procedural stepping + two-bone IK --------------------------------
class Foot:
    def __init__(self):
        self.x = 0.0          # offset from the rest spot, window space
        self.lift = 0.0
        self.toe = 0.0
        self.s = -1.0         # swing progress, <0 = planted
        self.x0 = self.x1 = 0.0
        self.dur = SWING_T
        self.h = 0.0


class Stepper:
    """Keeps both feet planted in the world while the body travels at v, and
    steps them: the trailing foot swings ahead once per STEP of distance; at a
    standstill, feet that are off their rest spot step back under the body."""

    def __init__(self):
        self.feet = [Foot(), Foot()]      # near, far
        self.reset()

    def reset(self):
        self.dist = 0.0
        self.next_at = 0.0
        self.lead = 0

    def phase(self):
        return clamp(1 - (self.next_at - self.dist) / STEP)

    def side(self):
        return 1 if self.lead == 1 else -1    # near foot swinging -> +1

    def settled(self):
        return all(f.s < 0 and abs(f.x) < 0.8 for f in self.feet)

    def _swing(self, f, to, dur, h):
        f.s, f.x0, f.x1, f.dur, f.h = 0.0, f.x, to, dur, h

    def update(self, dt, v, lock):
        if lock < 0.5:                        # airborne: feet regroup under the body
            for f in self.feet:
                f.x *= max(0.0, 1 - 14 * dt)
                f.lift = f.toe = 0.0
                f.s = -1.0
            return
        self.dist += v * dt
        for f in self.feet:
            if f.s < 0:
                f.x -= v * dt                 # planted: fixed in the world
        if v > 1.0:
            f = self.feet[self.lead]
            if self.dist >= self.next_at and f.s < 0:
                dur = min(SWING_T, 0.76 * STEP / v)
                self._swing(f, STEP - v * dur / 2, dur, 6.5)
                self.next_at += STEP * (0.8 if self.next_at == 0.0 else 1.0)
                self.lead ^= 1
        elif all(f.s < 0 for f in self.feet):
            f = max(self.feet, key=lambda f: abs(f.x))
            if abs(f.x) > 0.8:
                self._swing(f, 0.0, 0.22, 3.2)
        for f in self.feet:
            if f.s < 0:
                continue
            f.s += dt / f.dur
            s = min(1.0, f.s)
            f.x = f.x0 + (f.x1 - f.x0) * smooth(s)
            f.lift = f.h * math.sin(math.pi * s)
            # toes curl shut as the foot lifts, then open to meet the ground
            f.toe = (-24 * math.sin(math.pi * s) + 10 * bump((s - 0.6) / 0.4)) * f.h / 6.5
            if f.s >= 1.0:
                f.s, f.lift, f.toe = -1.0, 0.0, 0.0


def _ik(hx, hy, tx, ty):
    """Hip + ankle target -> (thigh, shin) rig angles, knee folding backward."""
    dx, dy = tx - hx, ty - hy
    d = clamp(math.hypot(dx, dy), 12.0, L1 + L2 - 0.05)
    base = math.atan2(dy, dx)
    ka = base + math.acos(clamp((L1 * L1 + d * d - L2 * L2) / (2 * L1 * d), -1.0, 1.0))
    kx, ky = hx + L1 * math.cos(ka), hy + L1 * math.sin(ka)
    ex, ey = hx + d * math.cos(base), hy + d * math.sin(base)
    th = math.degrees(ka) - REST_TH
    sh = math.degrees(math.atan2(ey - ky, ex - kx)) - REST_SH
    return wrap(th), wrap(sh - th)


def solve_legs(p, feet):
    """Turn the authored legs of pose p into final joint angles, in place.
    Hips ride the body transform; each ankle is blended between its planted
    spot (lock=1) and the authored airborne leg (lock=0), and never sinks
    below the ground."""
    px, py = BODY_PIVOT
    for leg, foot, hip, knee, ankle in ((p.near, feet[0], HIP_N, KNEE_N, ANKLE_N),
                                        (p.far, feet[1], HIP_F, KNEE_F, ANKLE_F)):
        rx, ry = rot2((hip[0] - px) * p.sx, (hip[1] - py) * p.sy, p.rot)
        hx, hy = px + rx + p.dx, py + ry + p.dy
        kx, ky = rot2(knee[0] - hip[0], knee[1] - hip[1], leg.thigh)
        ax, ay = rot2(ankle[0] - knee[0], ankle[1] - knee[1], leg.thigh + leg.shin)
        air_x, air_y = hx + kx + ax, hy + ky + ay
        gx, gy = ankle[0] + foot.x + leg.fx, ankle[1] - foot.lift + leg.fy
        tx = air_x + (gx - air_x) * p.lock
        ty = min(air_y + (gy - air_y) * p.lock, ankle[1])
        toe_abs = ((leg.thigh + leg.shin + leg.toes) * (1 - p.lock)
                   + (leg.toe + foot.toe) * p.lock)
        leg.thigh, leg.shin = _ik(hx, hy, tx, ty)
        leg.toes = toe_abs - leg.thigh - leg.shin
        leg.hx, leg.hy = hx - hip[0], hy - hip[1]


# ---- secondary motion, gaze, scheduling -------------------------------------
class Spring:
    """Second order follower; dt-based, stable at any fps."""
    def __init__(self, omega=12.0, zeta=0.7, value=0.0):
        self.omega, self.zeta = omega, zeta
        self.x = value
        self.v = 0.0

    def update(self, target, dt):
        n = max(1, int(dt * self.omega / 0.25) + 1)     # substep stiff springs
        h = dt / n
        for _ in range(n):
            a = self.omega * self.omega * (target - self.x) - 2 * self.zeta * self.omega * self.v
            self.v += a * h
            self.x += self.v * h
        return self.x


class Gaze:
    """Head saccades: brief ballistic snaps to a new fixation with a hair of
    overshoot, steady holds between (sourced: crow gaze, snaps >200 deg/s).
    Sometimes a quick double-take, sometimes a long curious cock of the head."""

    def __init__(self, rng):
        self.rng = rng
        self.sp = Spring(omega=55, zeta=0.6)
        self.target = 0.0
        self.next = 0.8 + rng.random()
        self.snapped = False          # true on the frame a saccade starts

    def update(self, t, dt, on):
        self.snapped = False
        if not on:
            self.target = 0.0
            self.next = t + 0.3 + self.rng.random() * 0.6
        elif t >= self.next:
            r = self.rng.random()
            if r < 0.22:              # head cock: big tilt, long look
                self.target = self.rng.choice((-17.0, 15.0))
                self.next = t + 1.2 + self.rng.random() * 1.6
            else:
                self.target = self.rng.uniform(-11.0, 11.0)
                gap = 0.22 + self.rng.random() * 0.2 if r < 0.42 else 0.7 + self.rng.random() * 2.3
                self.next = t + gap
            self.snapped = True
        return self.sp.update(self.target, dt)


class Scheduler:
    def __init__(self, seed=None):
        self.rng = random.Random(seed)
        self.repeat = 0
        self._last = 'idle'

    def next(self):
        if self.repeat > 0 and self._last in CHAINS:
            self.repeat -= 1
            return self._last
        if self._last == 'fly':
            self._last = 'flick'      # wing-tail flick right after landing (sourced)
            return 'flick'
        choices = [b for b in WEIGHTS if b != self._last]
        b = self.rng.choices(choices, weights=[WEIGHTS[c] for c in choices], k=1)[0]
        self.repeat = self.rng.randint(0, CHAINS.get(b, 0))
        self._last = b
        return b


class Animator:
    """Everything between 'which behavior' and 'final pose to draw'.

    update(dt) returns the solved Pose. vx is the forward travel speed in
    units/s (the caller moves the window by it). With auto=True it picks its
    own next behavior; on_start(behavior) fires on every behavior start.
    """
    BLEND_T = 0.2

    def __init__(self, seed=None, auto=True, on_start=None):
        self.rng = random.Random(seed)
        self.sched = Scheduler(seed)
        self.auto = auto
        self.on_start = on_start
        self.behavior = 'idle'
        self.t = 0.0
        self.t_total = 0.0
        self.done = False
        self.vx = 0.0
        self.drive = None                 # host-driven walk speed, units/s (None = own walks)
        self.walk_left = 0.0
        self._settle = 0.0
        self.prev = Pose()
        self.auth = pose_for('idle', 0.0)
        self.blend = 1.0
        self.pose = Pose()
        self.stepper = Stepper()
        self.gaze = Gaze(self.rng)
        self.gaze_on = {'idle', 'flick', 'jitter', 'flap'}
        self.tail_s = Spring(10, 0.5)
        self.wing_s = Spring(16, 0.6)
        self.spread_s = Spring(11, 0.65)
        self.head_s = Spring(30, 0.55)
        self.squash_s = Spring(20, 0.38, value=1.0)
        self.breath = 0.0
        self.exert = 0.0
        self.blink_t = -1.0
        self.next_blink = 1.5

    def start(self, behavior):
        self.exert = max(self.exert, EXERTION.get(self.behavior, 0.0))
        self.prev = self.auth
        self.blend = 0.0
        self.behavior = behavior
        self.t = 0.0
        self.done = False
        self._settle = 0.0
        if behavior == 'walk':
            self.stepper.reset()
            self.walk_left = STEP * self.rng.randint(4, 9)
        if self.on_start:
            self.on_start(behavior)

    def bounce(self, amount=1.0):
        """A squash impulse, e.g. when the bird is set down."""
        self.squash_s.v -= 2.2 * amount

    def _blink(self, dt):
        if self.blink_t < 0:
            if self.t_total < self.next_blink:
                return 0.0
            self.blink_t = 0.0
        self.blink_t += dt
        bt = self.blink_t
        if bt < 0.06:
            return bt / 0.06
        if bt < 0.10:
            return 1.0
        if bt < 0.20:
            return 1 - (bt - 0.10) / 0.10
        self.blink_t = -1.0
        double = self.rng.random() < 0.2
        self.next_blink = self.t_total + (0.1 if double else 1.8 + self.rng.random() * 4.0)
        return 0.0

    def update(self, dt):
        self.t += dt
        self.t_total += dt
        b = self.behavior

        # how the current behavior travels and ends
        v, gait = 0.0, (0.0, 0.0, 1)
        if b == 'walk':
            if self.drive is not None:
                v = self.drive                # the host moves the bird; just keep step with it
            elif self.walk_left > 0.4:
                v = WALK_V * min(smooth(self.t / 0.3), self.walk_left / 7.0)
            self.walk_left -= v * dt
            gait = (self.stepper.phase(), min(1.0, v / WALK_V), self.stepper.side())
            if v == 0.0 and self.stepper.settled():
                self._settle += dt
            finished = self.drive is None and (self._settle > 0.12 or self.t > DURATIONS['walk'])
        else:
            finished = self.t >= DURATIONS[b]
        if finished and not self.done:
            if self.auto:
                self.start(self.sched.next())
                return self.update(0.0)
            self.done = True

        raw = pose_for(b, self.t, gait)
        if self.blend < 1.0:
            self.blend = min(1.0, self.blend + dt / self.BLEND_T)
            raw = self.prev.mix(raw, smooth(self.blend))
        self.auth = raw
        p = raw.mix(raw, 0.0)                 # a copy to finish
        self.vx = v if b == 'walk' else p.vx

        # breathing never stops; faster and deeper after exertion
        self.exert *= math.exp(-dt / 3.5)
        self.breath += dt * TAU / 2.4 * (1 + 1.3 * self.exert)
        br = math.sin(self.breath) * (1 + 0.9 * self.exert)
        p.sx += 0.009 * br
        p.sy -= 0.006 * br
        p.dy -= 0.5 * br * p.lock
        p.beak += 2.5 * self.exert * max(0.0, br)

        # follow-through: body squash settles like jelly, tail lags the pitch,
        # feathers drag behind their commands, the head overshoots its nods
        sy = self.squash_s.update(p.sy, dt)
        p.sx += (p.sy - sy) * 0.7
        p.sy = sy
        p.tail = self.tail_s.update(p.tail - 0.55 * p.rot, dt)
        p.wing = self.wing_s.update(p.wing, dt)
        p.wing_spread = self.spread_s.update(p.wing_spread, dt)
        p.head_rot = self.head_s.update(p.head_rot, dt)
        p.head_rot += self.gaze.update(self.t_total, dt, b in self.gaze_on)
        if self.gaze.snapped and self.blink_t < 0 and self.rng.random() < 0.4:
            self.next_blink = self.t_total    # birds often blink on a head turn
        p.blink = max(p.blink, self._blink(dt))

        self.stepper.update(dt, v, p.lock)
        solve_legs(p, self.stepper.feet)
        self.pose = p
        return p
