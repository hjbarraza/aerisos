"""Re-check list for a map: entities and questions to revisit, plus matching of AERIS watchlist findings to entities.

    python3 -I watch.py <mapdir> list
    python3 -I watch.py <mapdir> add --entity ID | --question TEXT [--every DAYS] [--note TEXT]
    python3 -I watch.py <mapdir> remove ID
    python3 -I watch.py <mapdir> due                  # never checked, or last check older than every_days
    python3 -I watch.py <mapdir> mark ID              # last_checked = today
    python3 -I watch.py <mapdir> hits [--file PATH]   # AERIS findings that mention a map entity

Items live in <mapdir>/research/watch.json:
  [{id, kind: "entity"|"question", target, note, added, last_checked, every_days}]
`hits` only reads ~/.local/share/aeris/watchlist.json (the unreviewed findings in each item's "new" list,
as written by aeris-watch); it never writes it. data.js is only read.
"""
import json, os, re, subprocess, sys, unicodedata
from datetime import date, timedelta

HERE = os.path.dirname(os.path.abspath(__file__))
AERIS = os.path.expanduser("~/.local/share/aeris/watchlist.json")
EVERY = 90


def dump(data_js):
    out = subprocess.run(["node", os.path.join(HERE, "dump_data.js"), data_js], capture_output=True, text=True)
    if out.returncode:
        sys.exit("could not load data.js:\n" + out.stderr)
    return json.loads(out.stdout)


def merged_nodes(D):
    """Entities as the page sees them (ENRICH applied). Reduced from apply_patch.py's merged()."""
    X = D["ENRICH"] or {}
    nodes = {n["id"]: dict(n) for n in D["NODES"] + X.get("newNodes", [])}
    for i, x in X.get("entities", {}).items():
        if i in nodes:
            for k in ("label", "short"):
                if x.get(k):
                    nodes[i][k] = x[k]
    return nodes


def load(path):
    if not os.path.exists(path): return []
    try: return json.load(open(path, encoding="utf-8"))
    except ValueError as e: sys.exit(f"{path} is not valid JSON: {e}")


def save(path, items):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(items, f, ensure_ascii=False, indent=1); f.write("\n")
    os.replace(tmp, path)


def due_date(it):
    return None if not it.get("last_checked") else date.fromisoformat(it["last_checked"]) + timedelta(days=it.get("every_days", EVERY))


def row(it, nodes):
    t = it["target"]
    name = f"{t}  ({nodes[t]['label']})" if it["kind"] == "entity" and t in nodes else t
    d = due_date(it)
    return (f"{it['id']:<5} {it['kind']:<8} {name[:70]}  every {it.get('every_days', EVERY)}d, "
            f"checked {it.get('last_checked') or 'never'}{'' if d is None else ', due ' + d.isoformat()}" + (f"  # {it['note']}" if it.get("note") else ""))


def opt(args, flag):
    if flag not in args: return None
    i = args.index(flag)
    if i + 1 >= len(args): sys.exit(f"{flag} needs a value")
    return args[i + 1]


def fold(s):
    """Lowercase and strip accents so 'Končar' matches 'Koncar'."""
    return "".join(c for c in unicodedata.normalize("NFKD", s or "") if not unicodedata.combining(c)).replace("đ", "d").replace("Đ", "D")


def hits(nodes, mapdir, path):
    """(finding, entity id, name matched) for each unreviewed AERIS finding naming a map entity."""
    if not os.path.exists(path): sys.exit(f"no watchlist at {path}")
    W = json.load(open(path, encoding="utf-8"))
    names = []  # (regex, entity id, text), labels and shorts of 4+ chars, parenthetical removed as well as kept
    for i, n in nodes.items():
        for f in ("label", "short"):
            v = (n.get(f) or "").strip()
            for c in {v, re.sub(r"\s*\(.*?\)\s*", " ", v).strip()}:
                if len(c) >= 4: names.append((re.compile(r"(?<!\w)" + re.escape(fold(c)) + r"(?!\w)", re.I), i, c))
    out = []
    for item in W.get("items", []):
        for f in item.get("new", []):
            text = fold(f"{f.get('title', '')} {f.get('summary', '')}")
            seen = set()
            for rx, i, c in names:
                if i not in seen and rx.search(text):
                    seen.add(i); out.append((item["name"], f, i, c))
    return out


def main():
    a = sys.argv[1:]
    if len(a) < 2: sys.exit(__doc__)
    mapdir, cmd, rest = os.path.expanduser(a[0]), a[1], a[2:]
    path = os.path.join(mapdir, "research", "watch.json")
    nodes = merged_nodes(dump(os.path.join(mapdir, "data", "data.js")))
    items, today = load(path), date.today()
    mapname = os.path.basename(mapdir.rstrip("/"))

    if cmd == "list":
        for it in items: print(row(it, nodes))
        print(f"{len(items)} item(s)" if items else "nothing on the re-check list")
    elif cmd == "add":
        ent, q = opt(rest, "--entity"), opt(rest, "--question")
        if bool(ent) == bool(q): sys.exit("give exactly one of --entity ID or --question TEXT")
        if ent and ent not in nodes: sys.exit(f"unknown entity '{ent}' in {mapname}")
        try: every = int(opt(rest, "--every") or EVERY)
        except ValueError: sys.exit("--every must be a whole number of days")
        if every < 1: sys.exit("--every must be at least 1")
        kind, target = ("entity", ent) if ent else ("question", q.strip())
        if any(i["kind"] == kind and i["target"] == target for i in items): sys.exit(f"already on the list: {target}")
        n = 1 + max([int(i["id"][1:]) for i in items if re.fullmatch(r"w\d+", i["id"])] + [0])
        it = {"id": f"w{n}", "kind": kind, "target": target, "note": opt(rest, "--note") or "", "added": today.isoformat(),
              "last_checked": None, "every_days": every}
        save(path, items + [it]); print("added", row(it, nodes))
    elif cmd in ("remove", "mark"):
        if not rest: sys.exit(f"{cmd} needs an ID")
        hit = [i for i in items if i["id"] == rest[0]]
        if not hit: sys.exit(f"no item '{rest[0]}'")
        if cmd == "remove": items.remove(hit[0]); print("removed", hit[0]["id"])
        else: hit[0]["last_checked"] = today.isoformat(); print("marked", row(hit[0], nodes))
        save(path, items)
    elif cmd == "due":
        d = [i for i in items if due_date(i) is None or due_date(i) <= today]
        for it in d: print(row(it, nodes))
        print(f"{len(d)} due of {len(items)}")
    elif cmd == "hits":
        found = hits(nodes, mapdir, opt(rest, "--file") or AERIS)
        for src, f, i, c in found:
            link = f" | {f['link']}" if f.get("link") else ""
            print(f"{f.get('title', '?')[:110]}{link}\n  -> {i} ('{c}', from watch '{src}')"
                  f"\n  -> /map-research {mapname}: check whether this changes {i} ({nodes[i]['label']}): {f.get('title', '')[:90]}")
        print(f"{len(found)} hit(s) on {len(nodes)} entities" if found else "no unreviewed AERIS findings mention a map entity (findings sit in each item's 'new' list; run aeris-watch report)")
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
