"""Merge several research patches (and their -xref edge files) into one patch, resolving overlaps.

    python3 -I merge_patches.py out.json patch1.json patch2.json ... [--alias old=new ...] [--xref x1.json x2.json ...] [--map ~/maps/<map>]

Patches are merged in the order given (earlier wins on conflicts). Same node id: facts and sources are unioned.
`--map DIR` treats ids/sources already in that map (e.g. synced shared entities) as known.
`--alias old=new` renames ids before merging (e.g. two waves that named the same person differently).
Duplicate links (source, target, relation) are collapsed: the sources are unioned and the stronger grade
is NOT taken — the earlier patch's grade stays, so the owner of the domain decides. Links to unknown ids or unknown sources
(typically from xref files) and self-links are dropped and reported. Validate the result with apply_patch.py.
"""
import json, sys

args = sys.argv[1:]
out = args.pop(0)
alias, xref, patches, mode, mapdir = {}, [], [], "p", None
for a in args:
    if a == "--map": mode = "m"
    elif a == "--alias": mode = "a"
    elif a == "--xref": mode = "x"
    elif mode == "a" and "=" in a: k, v = a.split("=", 1); alias[k] = v
    elif mode == "m": mapdir = a; mode = "p"
    elif mode == "x": xref.append(a)
    else: patches.append(a)
A = lambda i: alias.get(i, i)

M = {"topic": "merged", "sources": {}, "rels": {}, "nodes": [], "edges": [], "update_nodes": [], "remove_edges": []}
nodes, edges = {}, {}
dropped = []
known, known_src = set(), set()
if mapdir:                                   # ids already in the map (e.g. shared entities) count as known
    sys.path.insert(0, __import__("os").path.dirname(__import__("os").path.abspath(__file__)))
    import apply_patch as ap
    _s, _r, _n, _e = ap.merged(ap.dump(__import__("os").path.join(__import__("os").path.expanduser(mapdir), "data", "data.js")))
    known, known_src = set(_n), set(_s)
Ps = [json.load(open(p, encoding="utf-8")) for p in patches]
M["topic"] = " + ".join(p.get("topic", "?") for p in Ps)[:120]
for P in Ps:
    for k, v in P.get("sources", {}).items(): M["sources"].setdefault(k, v)
    for k, v in P.get("rels", {}).items(): M["rels"].setdefault(k, v)
    for n in P.get("nodes", []):
        i = A(n["id"])
        if i in nodes:
            t = nodes[i]
            seen = {tuple(f) for f in t.get("facts", [])}
            t["facts"] = t.get("facts", []) + [f for f in n.get("facts", []) if tuple(f) not in seen and f[0] not in {x[0] for x in t.get("facts", [])}]
            t["src"] = list(dict.fromkeys(t.get("src", []) + n.get("src", [])))
        else:
            nodes[i] = {**n, "id": i}
    M["update_nodes"] += P.get("update_nodes", [])
    M["remove_edges"] += P.get("remove_edges", [])

def add_edges(L, where):
    for e in L:
        s, t, r, g, ss = A(e[0]), A(e[1]), e[2], e[3], e[4]
        if (s not in nodes and s not in known) or (t not in nodes and t not in known): dropped.append((where, s, t, r, "unknown node")); continue
        if s == t: dropped.append((where, s, t, r, "self-link")); continue
        if (bad := [x for x in ss if x not in M["sources"] and x not in known_src]): dropped.append((where, s, t, r, f"unknown source {bad}")); continue
        k = (s, t, r)
        if k in edges: edges[k][4] = list(dict.fromkeys(edges[k][4] + ss))
        else: edges[k] = [s, t, r, g, list(ss)]

for P in Ps: add_edges(P.get("edges", []), "main")
for x in xref: add_edges(json.load(open(x, encoding="utf-8")).get("edges", []), x.split("/")[-1])
M["nodes"] = list(nodes.values()); M["edges"] = list(edges.values())
for k in ("update_nodes", "remove_edges"):
    if not M[k]: del M[k]
json.dump(M, open(out, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
print(f"merged {len(Ps)} patches + {len(xref)} xref -> {out}: {len(M['nodes'])} nodes, {len(M['edges'])} links, {len(M['sources'])} sources")
for d in dropped: print("  dropped", *d)
