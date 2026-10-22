"""Merge duplicate entities in a map's data.js: redirect links, union facts and sources, drop the duplicate.

    python3 -I dedupe.py <mapdir> dup=keep [dup=keep ...]      (use `--auto` to merge audit look-alikes whose ids differ by prefix/suffix)

Backs up data.js first (data.js.bak-dedupe-<time>). Links that become duplicates or self-links are removed;
their sources are unioned into the surviving link. Works on one-entry-per-line NODES / E blocks as the tools write them.
"""
import json, os, re, shutil, sys, time

mapdir = os.path.expanduser(sys.argv[1])
pairs = dict(a.split("=", 1) for a in sys.argv[2:] if "=" in a)
path = os.path.join(mapdir, "data", "data.js")
shutil.copy2(path, f"{path}.bak-dedupe-{time.strftime('%H%M%S')}")
lines = open(path, encoding="utf-8").read().split("\n")
sec, nodes, order = None, {}, []
for l in lines:                                            # first pass: collect nodes to merge
    if l.startswith("const NODES"): sec = "N"
    elif l.startswith("const E ="): sec = "E"
    elif l.startswith("const ENRICH"): sec = None
    t = l.strip().rstrip(",")
    if sec == "N" and t.startswith("{"):
        n = json.loads(t); nodes[n["id"]] = n
for d, k in pairs.items():
    if d not in nodes or k not in nodes: sys.exit(f"unknown id in {d}={k}")
    K, D = nodes[k], nodes[d]
    seen = {f[0] for f in K.get("facts", [])}
    K["facts"] = K.get("facts", []) + [f for f in D.get("facts", []) if f[0] not in seen]
    K["src"] = list(dict.fromkeys(K.get("src", []) + D.get("src", [])))
    if not K.get("short") and D.get("short"): K["short"] = D["short"]
out, sec, seen_e, kept = [], None, {}, 0
for l in lines:
    if l.startswith("const NODES"): sec = "N"
    elif l.startswith("const E ="): sec = "E"
    elif l.startswith("const ENRICH"): sec = None
    t = l.strip().rstrip(",")
    if sec == "N" and t.startswith("{"):
        n = json.loads(t)
        if n["id"] in pairs: continue
        l = "  " + json.dumps(nodes[n["id"]], ensure_ascii=False) + ","
    elif sec == "E" and t.startswith("["):
        e = json.loads(t); e[0] = pairs.get(e[0], e[0]); e[1] = pairs.get(e[1], e[1])
        if e[0] == e[1]: continue
        key = tuple(e[:3])
        if key in seen_e:
            seen_e[key][4] = list(dict.fromkeys(seen_e[key][4] + e[4])); continue
        seen_e[key] = e; out.append(e); continue
    out.append(l)
res, buf = [], []
for x in out:                                              # re-emit edges with merged sources
    res.append("  " + json.dumps(x, ensure_ascii=False) + "," if isinstance(x, list) else x)
s = re.sub(r",(\s*\n\];)", r"\1", "\n".join(res))
open(path, "w", encoding="utf-8").write(s)
print(f"merged {len(pairs)} duplicate entities; backup kept")
