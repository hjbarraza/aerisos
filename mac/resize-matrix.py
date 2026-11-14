#!/usr/bin/env python3
"""Resize matrix: every window x every arrow x every layout (grid, float, tile) on the current
space, driven through Hammerspoon's aerisResize (the same code the hotkeys run).

Checks per case:
  grid  - a tiled window must not change size or place (it shakes and returns).
  float - the chosen edge moves in the arrow's direction; no other window changes.
  tile  - the chosen edge moves in the arrow's direction, unless the window spans the whole
          axis (nothing to resize) ; after every case no two tiled windows overlap and none
          leaves the work area (2 px slack).
Ends in tile, refocuses the original window. Don't touch mouse/keyboard while it runs.
"""
import json, subprocess, sys, time

Y = "/opt/homebrew/bin/yabai"
TOL = 2
HOLD = 0.3  # seconds the arrow is "held"


def q(*a):
    return json.loads(subprocess.run([Y, "-m", "query", *a], capture_output=True, text=True).stdout)


def sh(cmd):
    subprocess.run(cmd, shell=True, capture_output=True)


def wins():
    return {w["id"]: w for w in q("--windows", "--space")
            if w["is-visible"] and w["subrole"] == "AXStandardWindow"}


def E(f):
    return {"left": f["x"], "right": f["x"] + f["w"], "top": f["y"], "bottom": f["y"] + f["h"]}


d = q("--displays", "--display")["frame"]
WORK = {"left": d["x"] + 8, "right": d["x"] + d["w"] - 8, "top": d["y"] + 34, "bottom": d["y"] + d["h"] - 8}
# init.lua's edge test: work area + 2 px slack, 40 px from the edge counts as "on the edge".
S = {"left": d["x"] + 6, "right": d["x"] + d["w"] - 6, "top": d["y"] + 32, "bottom": d["y"] + d["h"] - 6}
SIGN = {"left": -1, "right": 1, "up": -1, "down": 1}
OPP = {"left": "right", "right": "left", "up": "down", "down": "up"}


def chosen_edge(f, dr):
    # Same rule as init.lua: right/bottom unless it sits on the screen edge, then left/top.
    e = E(f)
    if dr in ("left", "right"):
        return "left" if S["right"] - e["right"] < 40 and e["left"] - S["left"] >= 40 else "right"
    return "top" if S["bottom"] - e["bottom"] < 40 and e["top"] - S["top"] >= 40 else "bottom"


def spans(f, dr):
    e = E(f)
    if dr in ("left", "right"):
        return e["left"] - S["left"] < 40 and S["right"] - e["right"] < 40
    return e["top"] - S["top"] < 40 and S["bottom"] - e["bottom"] < 40


def hold(wid, dr):
    sh(f"{Y} -m window --focus {wid}")
    time.sleep(0.2)
    sh(f"hs -c \"aerisResize.start('{dr}'); hs.timer.doAfter({HOLD}, aerisResize.release)\"")
    time.sleep(HOLD + 0.8)


def tiled_problems(ws):
    t = [w for w in ws.values() if not w["is-floating"]]
    out = []
    for i, a in enumerate(t):
        ea = E(a["frame"])
        for s in ("left", "top"):
            if ea[s] < WORK[s] - TOL: out.append(f"{a['app']} past work-area {s} by {WORK[s]-ea[s]:.0f}")
        for s in ("right", "bottom"):
            if ea[s] > WORK[s] + TOL: out.append(f"{a['app']} past work-area {s} by {ea[s]-WORK[s]:.0f}")
        for b in t[i + 1:]:
            eb = E(b["frame"])
            ox = min(ea["right"], eb["right"]) - max(ea["left"], eb["left"])
            oy = min(ea["bottom"], eb["bottom"]) - max(ea["top"], eb["top"])
            if ox > TOL and oy > TOL: out.append(f"{a['app']} overlaps {b['app']} {ox:.0f}x{oy:.0f}")
    return out


def spill_score(ws):
    # Overlap area between tiled windows (beyond 2 px) + area past the work area.
    t = [E(w["frame"]) for w in ws.values() if not w["is-floating"]]
    sp = lambda a0, a1, b0, b1: max(min(a1, b1) - max(a0, b0), 0)
    total = 0
    for i, a in enumerate(t):
        total += (a["right"] - a["left"]) * (a["bottom"] - a["top"]) - sp(a["left"], a["right"], WORK["left"] - TOL, WORK["right"] + TOL) * sp(a["top"], a["bottom"], WORK["top"] - TOL, WORK["bottom"] + TOL)
        for b in t[i + 1:]:
            total += max(sp(a["left"], a["right"], b["left"], b["right"]) - TOL, 0) * max(sp(a["top"], a["bottom"], b["top"], b["bottom"]) - TOL, 0)
    return total


def same(a, b):
    return all(abs(E(a)[k] - E(b)[k]) <= TOL for k in ("left", "right", "top", "bottom"))


results = []


def run_layout(name):
    ws = wins()
    for wid in list(ws):
        for dr in ("left", "right", "up", "down"):
            before = wins()
            if wid not in before: continue
            w = before[wid]
            f = w["frame"]
            edge = chosen_edge(f, dr)
            hold(wid, dr)
            after = wins()
            fa = after[wid]["frame"]
            moved = (E(fa)[edge] - E(f)[edge]) * SIGN[dr]
            note = ""
            if name == "grid" and not w["is-floating"]:
                ok = all(same(before[i]["frame"], after[i]["frame"]) for i in before if i in after)
                note = "unchanged (shake)" if ok else "CHANGED"
            elif name == "float" or w["is-floating"]:
                others = all(same(before[i]["frame"], after[i]["frame"]) for i in before if i in after and i != wid)
                # Growing into the screen edge can't move the window further: that's the limit, not a bug.
                at_edge = (E(fa)[edge] - S[edge]) * SIGN[dr] >= -40
                ok = (moved >= 10 or at_edge) and others
                note = f"{edge} {moved:+.0f}px" + (" (at screen edge)" if moved < 10 and at_edge else "") + ("" if others else ", others moved")
            else:
                # Only a spill this case made worse is a failure; one left by the layout is not.
                probs = tiled_problems(after) if spill_score(after) > spill_score(before) else []
                if spans(f, dr):
                    ok = same(f, fa) and not probs
                    note = "spans axis, no change" if same(f, fa) else f"spans axis but changed {moved:+.0f}"
                elif moved < 10 and not probs:
                    # Did the guard stop it because a neighbour is at its minimum size? Probe one step.
                    step = {"left": "-20:0", "right": "20:0", "up": "0:-20", "down": "0:20"}[dr]
                    back = {"left": "20:0", "right": "-20:0", "up": "0:20", "down": "0:-20"}[dr]
                    sh(f"{Y} -m window {wid} --resize {edge}:{step}")
                    time.sleep(0.4)
                    probe = wins()
                    spilt = tiled_problems(probe) if spill_score(probe) > spill_score(after) else []
                    sh(f"{Y} -m window {wid} --resize {edge}:{back}")
                    time.sleep(0.4)
                    ok = bool(spilt)
                    note = f"{edge} {moved:+.0f}px, " + (f"blocked correctly ({spilt[0]})" if spilt else "NOT blocked by a spill")
                else:
                    ok = moved >= 10 and not probs
                    note = f"{edge} {moved:+.0f}px"
                if probs: note += " | " + "; ".join(probs)
            results.append((name, w["app"][:12], w["title"][:18], dr, "PASS" if ok else "FAIL", note))
            print(f"{name:5} {w['app'][:12]:12} {w['title'][:18]:18} {dr:5} {'PASS' if ok else 'FAIL'}  {note}", flush=True)
            # undo, so each case starts near the original layout
            if name != "grid" and moved: hold(wid, OPP[dr])
            time.sleep(0.5)  # let a late spill-undo land before the next case reads "before"


me = q("--windows", "--window")["id"]
LAYOUTS = (("grid", "~/.local/bin/grid"), ("float", "~/.local/bin/floating"), ("tile", "~/.local/bin/tile"))
for layout, cmd in [l for l in LAYOUTS if len(sys.argv) < 2 or l[0] in sys.argv[1:]]:
    sh(cmd)
    time.sleep(1.5)
    run_layout(layout)
sh(f"{Y} -m window --focus {me}")
fails = [r for r in results if r[4] == "FAIL"]
print(f"\n{len(results) - len(fails)}/{len(results)} passed")
