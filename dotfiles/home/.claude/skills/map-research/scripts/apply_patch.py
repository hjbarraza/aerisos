"""Validate a research patch against a map's data.js and (optionally) apply it.

    python3 -I apply_patch.py ~/maps/<map> patch.json            # dry run: validate + summary
    python3 -I apply_patch.py ~/maps/<map> patch.json --apply    # back up data.js, write, re-check
    ... --items 1-5,8        # dry run / apply only the numbered items (see the dry-run list)
    ... --reject             # log a rejected run (research/log.json); data.js untouched
    python3 -I apply_patch.py --undo ~/maps/<map> [--force]     # restore the last applied backup

Every --apply / --reject appends to <map>/research/log.json; --apply also records which patch
introduced each node/edge/update in <map>/research/provenance.json (data.js shapes unchanged).

New sources, relation types, entities and links go into the base blocks of data.js (SRC, REL,
NODES, E). Updates to existing entities and link removals go into the ENRICH overlay, which the
engine merges at load time (label/short/role/facts/note/status replace; src is unioned).
"""
import argparse, hashlib, json, os, re, shutil, subprocess, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
ID_RE = re.compile(r"^[a-z][a-z0-9_]*$")
NODE_KEYS = {"id", "label", "short", "kind", "d", "status", "role", "note", "facts", "src"}
UPDATE_KEYS = {"label", "short", "role", "note", "status"}


def dump(data_js):
    out = subprocess.run(["node", os.path.join(HERE, "dump_data.js"), data_js], capture_output=True, text=True)
    if out.returncode:
        sys.exit("could not load data.js:\n" + out.stderr)
    return json.loads(out.stdout)


def merged(D):
    """The graph as the page sees it (ENRICH applied)."""
    X = D["ENRICH"] or {}
    src = {**D["SRC"], **X.get("sources", {})}
    rel = {**D["REL"], **X.get("rels", {})}
    nodes = {n["id"]: dict(n) for n in D["NODES"] + X.get("newNodes", [])}
    for i, x in X.get("entities", {}).items():
        if i in nodes:
            for k in ("label", "short", "role", "facts", "note", "status"):
                if x.get(k):
                    nodes[i][k] = x[k]
            if x.get("src"):
                nodes[i]["src"] = list(dict.fromkeys((nodes[i].get("src") or []) + x["src"]))
    drop = {tuple(d) for d in X.get("drop", [])}
    edges = [e for e in D["E"] if tuple(e[:3]) not in drop] + X.get("relations", [])
    return src, rel, nodes, edges


def norm(s):
    return re.sub(r"[^a-z0-9]+", " ", re.sub(r"\(.*?\)", "", (s or "").lower())).strip()


def validate(D, P):
    errs, warns = [], []
    src, rel, nodes, edges = merged(D)
    kinds, domains, grades = set(D["KINDS"]), set(D["DOMAINS"]), set(D["CONF"])
    statuses = {n.get("status") for n in nodes.values()} | {"active", "former", "unverified"}
    url_to_key = {v[1]: k for k, v in src.items()}

    new_src = P.get("sources", {})
    for k, v in new_src.items():
        if not ID_RE.match(k): errs.append(f"source key '{k}' must match {ID_RE.pattern}")
        if k in src: errs.append(f"source key '{k}' already exists")
        if not (isinstance(v, list) and len(v) == 2 and str(v[1]).startswith("http")):
            errs.append(f"source '{k}' must be [\"title, date\", \"https://...\"]")
        elif v[1] in url_to_key:
            warns.append(f"source '{k}' URL already cited as '{url_to_key[v[1]]}' — reuse that key")
    all_src = {**src, **new_src}

    new_rel = P.get("rels", {})
    for k, v in new_rel.items():
        if k in rel: errs.append(f"relation '{k}' already exists")
        if not (isinstance(v, list) and len(v) == 4): errs.append(f"relation '{k}' must be [active, reverse, types, meaning]")
    all_rel = {**rel, **new_rel}

    new_ids = set()
    labels = {norm(n.get("label")): i for i, n in nodes.items()} | {norm(n.get("short")): i for i, n in nodes.items() if n.get("short")}
    for n in P.get("nodes", []):
        i = n.get("id", "")
        if not ID_RE.match(i): errs.append(f"node id '{i}' must match {ID_RE.pattern}")
        if i in nodes or i in new_ids: errs.append(f"node id '{i}' already exists")
        new_ids.add(i)
        if extra := set(n) - NODE_KEYS: errs.append(f"node '{i}': unknown fields {sorted(extra)}")
        for f in ("label", "kind", "d", "status", "role", "src"):
            if not n.get(f): errs.append(f"node '{i}': missing {f}")
        if n.get("kind") not in kinds: errs.append(f"node '{i}': kind '{n.get('kind')}' not in {sorted(kinds)}")
        if n.get("d") not in domains: errs.append(f"node '{i}': domain '{n.get('d')}' not in {sorted(domains)}")
        if n.get("status") not in statuses: warns.append(f"node '{i}': unusual status '{n.get('status')}'")
        for s in n.get("src", []):
            if s not in all_src: errs.append(f"node '{i}': unknown source '{s}'")
        for f in n.get("facts", []):
            if not (isinstance(f, list) and len(f) == 2): errs.append(f"node '{i}': facts must be [label, value] pairs")
        hit = labels.get(norm(n.get("label"))) or (n.get("short") and labels.get(norm(n.get("short"))))
        if hit: warns.append(f"node '{i}' ('{n.get('label')}') looks like existing '{hit}' ('{nodes[hit]['label']}')")
    all_ids = set(nodes) | new_ids

    for u in P.get("update_nodes", []):
        i = u.get("id")
        if i not in nodes: errs.append(f"update: unknown node '{i}'"); continue
        if extra := set(u.get("set", {})) - UPDATE_KEYS: errs.append(f"update '{i}': cannot set {sorted(extra)}")
        for s in u.get("add_src", []):
            if s not in all_src: errs.append(f"update '{i}': unknown source '{s}'")
        if u.get("add_facts") and not u.get("add_src"): warns.append(f"update '{i}': new facts without add_src")

    existing = {tuple(e[:3]) for e in edges}
    for e in P.get("edges", []):
        if not (isinstance(e, list) and len(e) == 5): errs.append(f"edge {e}: must be [source, target, rel, grade, [sources]]"); continue
        s, t, r, g, ss = e
        for x in (s, t):
            if x not in all_ids: errs.append(f"edge {s}→{t}: unknown node '{x}'")
        if s == t: errs.append(f"edge {s}→{t}: self-link")
        if r not in all_rel: errs.append(f"edge {s}→{t}: relation '{r}' not defined (add it under rels)")
        if g not in grades: errs.append(f"edge {s}→{t}: grade '{g}' not in {sorted(grades)}")
        if not ss: errs.append(f"edge {s}→{t}: no sources")
        for k in ss:
            if k not in all_src: errs.append(f"edge {s}→{t}: unknown source '{k}'")
        if (s, t, r) in existing: errs.append(f"edge {s}→{t} {r}: already exists")
        existing.add((s, t, r))

    for d in P.get("remove_edges", []):
        if tuple(d[:3]) not in {tuple(e[:3]) for e in edges}: errs.append(f"remove_edges {d}: no such link")

    linked = {x for e in edges + P.get("edges", []) for x in e[:2]}
    for i in new_ids - linked:
        warns.append(f"node '{i}' has no links — it will float unconnected")
    return errs, warns


def insert_block(s, start, text):
    i = s.index(start); j = s.index("\n};" if start.rstrip().endswith("{") else "\n];", i)
    k = j
    while True:                       # insert after the last real entry, not after trailing // comment lines
        while s[k - 1] in " \n": k -= 1
        ls = s.rfind("\n", 0, k) + 1
        if s[ls:k].lstrip().startswith("//") and ls > i: k = ls
        else: break
    sep = "" if s[k - 1] in ",{[" else ","
    return s[:k] + sep + "\n" + text + s[k:]


def apply(data_js, D, P):
    J = lambda o: json.dumps(o, ensure_ascii=False)
    s = open(data_js, encoding="utf-8").read()
    tag = P.get("topic", "research patch")
    if P.get("sources"): s = insert_block(s, "const SRC = {", ",\n".join(f"  {k}:{J(v)}" for k, v in P["sources"].items()))
    if P.get("rels"): s = insert_block(s, "const REL = {", ",\n".join(f"  {k}:{J(v)}" for k, v in P["rels"].items()))
    if P.get("nodes"): s = insert_block(s, "const NODES = [", f"  // {tag}\n" + ",\n".join("  " + J(n) for n in P["nodes"]))
    if P.get("edges"): s = insert_block(s, "const E = [", ",\n".join("  " + J(e) for e in P["edges"]))
    if P.get("update_nodes") or P.get("remove_edges"):
        _, _, nodes, _ = merged(D)
        X = D["ENRICH"] or {"sources": {}, "rels": {}, "entities": {}, "newNodes": [], "relations": []}
        X.setdefault("drop", [])
        for u in P.get("update_nodes", []):
            ent = X["entities"].setdefault(u["id"], {})
            ent.update(u.get("set", {}))
            if u.get("add_facts"):
                ent["facts"] = (nodes[u["id"]].get("facts") or []) + u["add_facts"]
            if u.get("add_src"):
                ent["src"] = list(dict.fromkeys(ent.get("src", []) + u["add_src"]))
        X["drop"] += [list(d[:3]) for d in P.get("remove_edges", [])]
        line = "const ENRICH = " + J(X) + ";"
        if re.search(r"^const ENRICH = .*$", s, re.M):
            s = re.sub(r"^const ENRICH = .*$", lambda m: line, s, count=1, flags=re.M)
        else:
            s = s.rstrip() + "\n" + line + "\n"
    open(data_js, "w", encoding="utf-8").write(s)


def sha(path):
    return hashlib.sha256(open(path, "rb").read()).hexdigest()


def read_json(path, default):
    return json.load(open(path, encoding="utf-8")) if os.path.exists(path) else default


def write_json(path, obj):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, "w", encoding="utf-8").write(json.dumps(obj, ensure_ascii=False, indent=1) + "\n")


def items_of(P):
    """Numbered patch items: new nodes, edges, update_nodes, remove_edges, numbered in that order."""
    out = []
    for kind, key in (("node", "nodes"), ("edge", "edges"), ("update", "update_nodes"), ("remove", "remove_edges")):
        for x in P.get(key, []):
            out.append((len(out) + 1, kind, x))
    return out


def describe(kind, x):
    if kind == "node": return f"+ entity {x.get('id')}: {x.get('label')} [{x.get('kind')}/{x.get('d')}]"
    if kind == "edge": return f"+ link {x[0]} -{x[2]}-> {x[1]} ({x[3]})" if isinstance(x, list) and len(x) == 5 else f"+ link {x}"
    if kind == "update": return f"~ update {x.get('id')}: set {sorted(x.get('set', {}))}" + (" +facts" if x.get("add_facts") else "") + (" +src" if x.get("add_src") else "")
    return f"- remove link {'|'.join(map(str, x[:3]))}"


def parse_items(spec, total):
    sel = set()
    for part in spec.split(","):
        m = re.fullmatch(r"\s*(\d+)(?:-(\d+))?\s*", part)
        if not m: sys.exit(f"bad --items '{spec}' (use e.g. 1-5,8)")
        a, b = int(m[1]), int(m[2] or m[1])
        if a > b or a < 1 or b > total: sys.exit(f"--items {part}: out of range 1-{total}")
        sel |= set(range(a, b + 1))
    return sel


def select(P, sel):
    """Filtered patch holding only the selected items plus the sources/rels they reference.
    Returns (patch, dependency errors)."""
    its = items_of(P)
    pick = lambda kind: [x for n, k, x in its if k == kind and n in sel]
    Q = {"topic": P.get("topic"), "nodes": pick("node"), "edges": pick("edge"),
         "update_nodes": pick("update"), "remove_edges": pick("remove")}
    errs = []
    chosen = {n["id"] for n in Q["nodes"]}
    in_patch = {n.get("id") for n in P.get("nodes", [])}
    num = {id(x): n for n, k, x in its}
    for e in Q["edges"]:
        for x in e[:2]:
            if x in in_patch and x not in chosen:
                errs.append(f"item {num[id(e)]} (link {e[0]}->{e[1]}) needs new entity '{x}' which is not selected")
    used = {s for n in Q["nodes"] for s in n.get("src", [])} | {s for e in Q["edges"] for s in e[4]} \
        | {s for u in Q["update_nodes"] for s in u.get("add_src", [])}
    Q["sources"] = {k: v for k, v in P.get("sources", {}).items() if k in used}
    Q["rels"] = {k: v for k, v in P.get("rels", {}).items() if k in {e[2] for e in Q["edges"]}}
    return Q, errs


def counts(P):
    return {"sources": len(P.get("sources", {})), "rels": len(P.get("rels", {})), "nodes": len(P.get("nodes", [])),
            "edges": len(P.get("edges", [])), "updates": len(P.get("update_nodes", [])), "removed_edges": len(P.get("remove_edges", []))}


def log_add(mapdir, entry):
    path = os.path.join(mapdir, "research", "log.json")
    log = read_json(path, [])
    log.append(entry)
    write_json(path, log)


def prov_keys(P):
    return {"nodes": [n["id"] for n in P.get("nodes", [])], "edges": ["|".join(e[:3]) for e in P.get("edges", [])],
            "updates": [u["id"] for u in P.get("update_nodes", [])]}


def prov_add(mapdir, name, keys):
    path = os.path.join(mapdir, "research", "provenance.json")
    pv = read_json(path, {})
    for k in ("nodes", "edges", "updates"): pv.setdefault(k, {})
    for i in keys["nodes"]: pv["nodes"][i] = name
    for i in keys["edges"]: pv["edges"][i] = name
    for i in keys["updates"]: pv["updates"].setdefault(i, []).append(name)
    write_json(path, pv)


def prov_strip(mapdir, name, keys):
    path = os.path.join(mapdir, "research", "provenance.json")
    pv = read_json(path, {"nodes": {}, "edges": {}, "updates": {}})
    for i in keys.get("nodes", []):
        if pv["nodes"].get(i) == name: del pv["nodes"][i]
    for i in keys.get("edges", []):
        if pv["edges"].get(i) == name: del pv["edges"][i]
    for i in keys.get("updates", []):
        if name in pv["updates"].get(i, []):
            pv["updates"][i].remove(name)
            if not pv["updates"][i]: del pv["updates"][i]
    write_json(path, pv)


def undo(mapdir, force):
    data_js = os.path.join(mapdir, "data", "data.js")
    path = os.path.join(mapdir, "research", "log.json")
    log = read_json(path, [])
    ent = next((e for e in reversed(log) if e["outcome"] in ("applied", "partly applied")), None)
    if not ent: sys.exit("nothing to undo: no applied entry in log")
    bak = os.path.join(os.path.dirname(data_js), ent["backup"] or "")
    if not ent["backup"] or not os.path.exists(bak): sys.exit(f"backup {ent['backup']} missing; cannot undo")
    if sha(data_js) != ent.get("sha_after") and not force:
        sys.exit(f"refusing: data.js changed since {ent['id']} was applied (sha mismatch); use --force to restore anyway")
    shutil.copy2(bak, data_js)
    ent["outcome"] = "reverted"
    write_json(path, log)
    prov_strip(mapdir, ent["patch"], ent.get("prov", {}))
    _, _, nodes, edges = merged(dump(data_js))
    c = ent["counts"]
    print(f"reverted {ent['id']} '{ent['question']}' ({ent['patch']}); restored {ent['backup']} (kept)")
    print(f"  removed +{c['nodes']} entities, +{c['edges']} links, {c['updates']} updates, -{c['removed_edges']} links undone")
    print(f"now: {len(nodes)} entities, {len(edges)} links")


def main():
    ap = argparse.ArgumentParser(usage="apply_patch.py <mapdir> <patch.json> [--apply|--reject] [--items 1-5,8] | --undo <mapdir> [--force]")
    ap.add_argument("mapdir"); ap.add_argument("patch", nargs="?")
    ap.add_argument("--apply", action="store_true"); ap.add_argument("--reject", action="store_true")
    ap.add_argument("--items"); ap.add_argument("--undo", action="store_true"); ap.add_argument("--force", action="store_true")
    a = ap.parse_args()
    mapdir = os.path.abspath(os.path.expanduser(a.mapdir))
    if a.undo: return undo(mapdir, a.force)
    if not a.patch: sys.exit(__doc__)
    data_js = os.path.join(mapdir, "data", "data.js")
    try:
        P0 = json.load(open(a.patch, encoding="utf-8"))
    except (OSError, ValueError) as e:
        sys.exit(f"cannot read patch {a.patch}: {e}")
    D = dump(data_js)
    name, stamp = os.path.basename(a.patch), time.strftime("%Y%m%d-%H%M%S")
    its = items_of(P0)
    print(f"patch '{P0.get('topic', '?')}' → {data_js}")
    for n, k, x in its: print(f"  {n:>3}. {describe(k, x)}")
    sel = parse_items(a.items, len(its)) if a.items else None
    if sel:
        P, derrs = select(P0, sel)
    else:
        P, derrs = P0, []
    c = counts(P)
    print(f"  {'selected' if sel else 'all'}: +{c['sources']} sources, +{c['rels']} relation types, +{c['nodes']} entities, "
          f"+{c['edges']} links, {c['updates']} updates, -{c['removed_edges']} links")
    errs, warns = validate(D, P)
    errs = derrs + errs
    for w in warns: print("  WARN ", w)
    for e in errs: print("  ERROR", e)
    if a.reject:
        log_add(mapdir, {"id": stamp, "date": time.strftime("%Y-%m-%dT%H:%M:%S"), "question": P0.get("topic"), "patch": name,
                         "outcome": "rejected", "applied_items": [], "backup": None, "counts": counts(P0)})
        print(f"rejected: logged {stamp} in research/log.json; data.js untouched"); return
    if errs: sys.exit(f"{len(errs)} error(s); nothing written")
    if not a.apply:
        print("dry run OK (use --apply to write)"); return
    bak = f"{data_js}.bak-{stamp}"
    shutil.copy2(data_js, bak)
    apply(data_js, D, P)
    _, _, nodes, edges = merged(dump(data_js))
    bad = [e for e in edges if e[0] not in nodes or e[1] not in nodes]
    if bad:
        shutil.copy2(bak, data_js); sys.exit(f"post-write check failed {bad[:3]}; restored {bak}")
    keys = prov_keys(P)
    prov_add(mapdir, name, keys)
    log_add(mapdir, {"id": stamp, "date": time.strftime("%Y-%m-%dT%H:%M:%S"), "question": P0.get("topic"), "patch": name,
                     "outcome": "partly applied" if sel else "applied", "applied_items": sorted(sel) if sel else None,
                     "backup": os.path.basename(bak), "counts": c, "sha_after": sha(data_js), "prov": keys,
                     "gaps": P0.get("gaps", [])})
    print(f"applied{' (partly: items ' + a.items + ')' if sel else ''}. backup: {bak}\nnow: {len(nodes)} entities, {len(edges)} links")


if __name__ == "__main__":
    main()
