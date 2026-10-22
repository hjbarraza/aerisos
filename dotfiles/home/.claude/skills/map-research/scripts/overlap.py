"""Cross-map overlap check: shared entities (exact normalised label/short), shared source URLs and hosts.

    python3 -I overlap.py [mapdir ...]        # default: every ~/maps/*/data/data.js

Prints per pair of maps: exact label matches (candidates for a shared core) and shared source URLs.
Generic words are not matched fuzzily on purpose; label matches still need a human look
(e.g. 'Ministry of Defence' in two countries is a false positive).
Pairs already ruled on in ~/maps/shared/identity.json (confirmed or rejected) are counted but
not re-proposed; new rulings go into that file through the normal review gate.
"""
import glob, itertools, json, os, re, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import apply_patch as ap

# identity.json rulings: confirmed pairs are already merged, rejected pairs are ruled distinct — neither is re-proposed
try:
    _ident = json.load(open(os.path.expanduser("~/maps/shared/identity.json"), encoding="utf-8"))
except (OSError, ValueError):
    _ident = {}
RULED = {}
for _k, _v in _ident.items():
    if _k.startswith("_"): continue
    _ms = [tuple(m) for m in _v.get("members", [])]
    for _a, _b in itertools.combinations(sorted(_ms), 2):
        RULED[(_a, _b)] = (_v.get("status"), _k)

dirs = [os.path.expanduser(d) for d in sys.argv[1:]] or sorted(os.path.dirname(os.path.dirname(p)) for p in glob.glob(os.path.expanduser("~/maps/*/data/data.js")))
M = {}
for d in dirs:
    src, rel, nodes, edges = ap.merged(ap.dump(os.path.join(d, "data", "data.js")))
    L = {}
    for i, n in nodes.items():
        for l in (n.get("label"), n.get("short")):
            if l and len(ap.norm(l)) > 3: L.setdefault(ap.norm(l), i)
    M[os.path.basename(d)] = (nodes, src, L)
total = 0
for a, b in itertools.combinations(M, 2):
    (na, sa, la), (nb, sb, lb) = M[a], M[b]
    hit, ruled = [], []
    for k in sorted(la.keys() & lb.keys()):
        pair = tuple(sorted([(a, la[k]), (b, lb[k])]))
        (ruled if pair in RULED else hit).append((la[k], lb[k]))
    hit = sorted(set(hit)); ruled = sorted(set(ruled))
    urls = {v[1].rstrip("/") for v in sa.values()} & {v[1].rstrip("/") for v in sb.values()}
    total += len(hit)
    print(f"{a} x {b}: {len(hit)} suggestions, {len(ruled)} already ruled in identity.json, {len(urls)} shared source URLs")
    for x, y in hit: print(f"   suggest {x} ({na[x]['label']})  <>  {y} ({nb[y]['label']})   -> record the ruling in ~/maps/shared/identity.json")
    for u in sorted(urls)[:10]: print("   url", u)
print(f"total label matches: {total}  (threshold to consider a shared core: >15-20 real repeats)")
