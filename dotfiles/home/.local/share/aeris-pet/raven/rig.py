"""The tinyraven desktop bird for aeris-pet: the chubby raven of the bar, drawn with cairo.

anim.py (next to this file, shared with crowpet) decides how the bird moves and hands
back a solved Pose: planted feet and steps, head swing, blinks, breathing, squash and
follow-through. draw() turns a Pose into the same round little bird that lives in the bar
(Bar/PetLane.qml drawRaven): small and round, but a raven: heavy bill, throat beard, long
wedge tail, long wings. The bar's shapes are these divided by 9.6; keep the two alike.

Coordinates are anim.py's rig units, y down, facing +x, with the feet at
(FEET_X, GROUND_Y). The caller scales the context; the bird stands about 130 units tall.
The legs come from the rig's leg solve, so the feet land where anim.py planted them; the
round body simply hangs low and hides most of the leg.
"""
import math

import cairo

from anim import ANKLE_F, ANKLE_N, BODY_PIVOT, HIP_F, HIP_N, KNEE_F, KNEE_N, rot2

FEET_X, GROUND_Y = 6.2, 62.0         # the line between the feet, and the floor under them
# What makes it a raven and not a chick: a heavy bill as long as the head, a throat beard,
# a long wedge of a tail, wings that reach back over it, and a body carried chest-up.
BODY = (0.0, 8.0, 50.0, 29.0, -16.0)     # oval: center x, y, radius x, y, tilt (chest up)
NECK_P = (20.0, -10.0)               # the head swings about this point
HEAD_C, HEAD_R = (38.0, -30.0), 23.0
# from the head center. Bill: the top edge is a curve (forehead, two controls, tip)
BILL_TOP = ((10.0, -15.0), (28.0, -19.0), (47.0, -11.0), (52.0, 5.0))
BILL_HINGE, BILL_LOW = (13.0, 2.0), ((45.0, 7.0), (11.0, 13.0))      # jaw tip, jaw base
BEARD = ((1.0, 18.0), (12.0, 30.0), (21.0, 11.0))
EYE, EYE_R = (3.0, -7.0), 5.2
WING_P = (8.0, -10.0)                # shoulder
# from the shoulder: a long pointed wing, tip resting over the tail (start, then two curves)
WING = ((12.0, -8.0), ((-12.0, -22.0), (-46.0, -4.0), (-72.0, 24.0)), ((-46.0, 27.0), (-10.0, 23.0), (12.0, -8.0)))
TAIL_P = (-40.0, 18.0)
TAIL = ((6.0, -11.0), (-56.0, 1.0), (-63.0, 11.0), (-55.0, 22.0), (4.0, 13.0))   # from the tail base
TAIL_LINES = (((-12.0, 4.0), (-56.0, 9.0)), ((-10.0, 9.0), (-52.0, 16.0)))

WHITE, WING_FILL, GREY, DARK, EYE_FILL = (1.0, 1.0, 1.0), (0.9, 0.9, 0.9), (0.5, 0.5, 0.5), (0.34, 0.34, 0.34), (0.04, 0.04, 0.04)
OUTLINE, LEG_W = 13.0, 7.0           # the outline is stroked under the fill, so half of it shows


def draw(cr, pose):
    """Draw one solved pose, in rig units."""
    def oval(x, y, rx, ry, tilt=0.0):
        cr.save()
        cr.translate(x, y); cr.rotate(math.radians(tilt)); cr.scale(rx, ry)
        cr.new_sub_path(); cr.arc(0, 0, 1, 0, 2 * math.pi)
        cr.restore()

    def poly(pts, ox=0.0, oy=0.0):
        cr.new_sub_path()
        for x, y in pts:
            cr.line_to(ox + x, oy + y)
        cr.close_path()

    cr.set_line_cap(cairo.LINE_CAP_ROUND)
    cr.set_line_join(cairo.LINE_JOIN_ROUND)

    # legs: hip, backward-bending joint, ankle and toes, exactly where the rig solved them
    cr.set_source_rgb(*DARK)
    cr.set_line_width(LEG_W)
    for leg, hip, knee, ankle in ((pose.far, HIP_F, KNEE_F, ANKLE_F), (pose.near, HIP_N, KNEE_N, ANKLE_N)):
        hx, hy = hip[0] + leg.hx, hip[1] + leg.hy
        kx, ky = rot2(knee[0] - hip[0], knee[1] - hip[1], leg.thigh)
        ax, ay = rot2(ankle[0] - knee[0], ankle[1] - knee[1], leg.thigh + leg.shin)
        fx, fy = hx + kx + ax, hy + ky + ay
        cr.move_to(hx, hy); cr.line_to(hx + kx, hy + ky); cr.line_to(fx, fy)
        tx, ty = rot2(17.0, 0.0, leg.thigh + leg.shin + leg.toes)
        cr.line_to(fx + tx, fy + ty)
        cr.move_to(fx, fy); cr.line_to(fx - tx * 0.4, fy - ty * 0.4)        # back toe
        cr.stroke()

    cr.save()
    cr.translate(pose.dx, pose.dy)
    cr.translate(*BODY_PIVOT); cr.rotate(math.radians(pose.rot)); cr.scale(pose.sx, pose.sy)
    cr.translate(-BODY_PIVOT[0], -BODY_PIVOT[1])

    # head: swung about the neck base, plus any reach
    hx, hy = rot2(HEAD_C[0] - NECK_P[0], HEAD_C[1] - NECK_P[1], pose.head_rot)
    hx, hy = NECK_P[0] + hx + pose.head_dx, NECK_P[1] + hy + pose.head_dy

    def skin():
        cr.save()
        cr.translate(*TAIL_P); cr.rotate(math.radians(pose.tail)); poly(TAIL)
        cr.restore()
        oval(*BODY)
        oval(hx, hy, HEAD_R, HEAD_R)
        cr.save()
        cr.translate(hx, hy); cr.rotate(math.radians(pose.head_rot)); poly(BEARD)
        cr.restore()

    # tail, body, head and beard share one outline: all outlines first, then all fills
    cr.set_line_width(OUTLINE)
    cr.set_source_rgb(*GREY)
    skin(); cr.stroke()
    cr.set_source_rgb(*WHITE)
    skin(); cr.fill()
    cr.save()                                # tail feathers
    cr.translate(*TAIL_P); cr.rotate(math.radians(pose.tail))
    cr.set_source_rgb(*GREY)
    cr.set_line_width(3.5)
    for a, b in TAIL_LINES:
        cr.move_to(*a); cr.line_to(*b)
    cr.stroke()
    cr.restore()

    # wing: folded along the body, opens (length, width) and swings up to beat
    cr.save()
    cr.translate(*WING_P); cr.rotate(math.radians(pose.wing)); cr.scale(pose.wing_spread, pose.wing_w)
    start, c1, c2 = WING
    cr.move_to(*start); cr.curve_to(*c1[0], *c1[1], *c1[2]); cr.curve_to(*c2[0], *c2[1], *c2[2])
    cr.close_path()
    cr.restore()
    cr.set_source_rgb(*WING_FILL)
    cr.fill_preserve()
    cr.set_source_rgb(*GREY)
    cr.set_line_width(OUTLINE / 2)
    cr.stroke()

    # face: rides the head. The bill is two halves about a hinge, so it opens
    cr.translate(hx, hy)
    cr.rotate(math.radians(pose.head_rot))
    cr.set_source_rgb(*DARK)
    cr.save()                                # upper bill lifts a little
    cr.translate(*BILL_HINGE); cr.rotate(math.radians(-0.2 * pose.beak)); cr.translate(-BILL_HINGE[0], -BILL_HINGE[1])
    p0, p1, p2, p3 = BILL_TOP
    cr.move_to(*p0); cr.curve_to(*p1, *p2, *p3); cr.line_to(*BILL_HINGE); cr.close_path()
    cr.fill()
    cr.restore()
    cr.save()                                # jaw drops
    cr.translate(*BILL_HINGE); cr.rotate(math.radians(0.8 * pose.beak)); cr.translate(-BILL_HINGE[0], -BILL_HINGE[1])
    cr.move_to(*BILL_HINGE); cr.line_to(*BILL_LOW[0]); cr.line_to(*BILL_LOW[1]); cr.close_path()
    cr.fill()
    cr.restore()
    cr.set_source_rgb(*EYE_FILL)
    if pose.blink > 0.5:                     # a closed eye is a small line
        cr.set_line_width(3.5)
        cr.move_to(EYE[0] - EYE_R, EYE[1]); cr.line_to(EYE[0] + EYE_R, EYE[1])
        cr.stroke()
    else:
        oval(EYE[0], EYE[1], EYE_R, EYE_R * (1 - pose.blink))
        cr.fill()
    cr.restore()
