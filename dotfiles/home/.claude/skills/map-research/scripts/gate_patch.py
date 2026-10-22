"""Pre-apply grade gate for a (merged) patch: downgrade `doc` links that cite no official-looking source to `press`.

    python3 -I gate_patch.py patch.json [--official host-fragment ...] [--drop node_id ...]

A source is official-looking if its URL contains .gov, gov., .mil, mil., gouv, gob., .int, europa.eu, parliament,
court, or a --official fragment (add the country's own domains, e.g. kaitseministeerium.ee riigiteataja.ee).
--drop removes nodes (and their links), e.g. private individuals. Edits the file in place and prints counts.
"""
import json, sys

a = sys.argv[1:]
path = a.pop(0)
official, drop, mode = [], set(), None
for x in a:
    if x == "--official": mode = "o"
    elif x == "--drop": mode = "d"
    elif mode == "o": official.append(x)
    elif mode == "d": drop.add(x)
BASE = (".gov", "gov.", ".mil", "mil.", "gouv", "gob.", ".int", "europa.eu", "parliament", "court", "justice.", "treasury.", "govinfo", "federalregister")
P = json.load(open(path, encoding="utf-8"))
S = P["sources"]
ok = lambda k: any(f in S[k][1].split("/")[2] + "/" + S[k][1].split("/", 3)[-1] for f in BASE + tuple(official)) if k in S else False
n = 0
for e in P["edges"]:
    if e[3] == "doc" and not any(ok(k) for k in e[4]):
        e[3] = "press"; n += 1
P["nodes"] = [x for x in P["nodes"] if x["id"] not in drop]
P["edges"] = [e for e in P["edges"] if not set(e[:2]) & drop]
json.dump(P, open(path, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
print(f"downgraded {n} doc links to press; dropped {len(drop)} nodes; {len(P['nodes'])} nodes, {len(P['edges'])} links")
