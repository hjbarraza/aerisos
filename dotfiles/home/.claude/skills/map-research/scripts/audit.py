"""Read-only quality audit of a map's merged graph (data.js with ENRICH applied).

    python3 -I audit.py ~/maps/<map>            # text report, 25 rows per section
    python3 -I audit.py ~/maps/<map> --json     # machine output, no row cap

Sections: a) stale/undated sources, b) weak entities, c) orphans, d) links graded above their
sources, e) duplicate entities and sources. Everything is a heuristic to review, never a verdict.
Nothing is written.
"""
import json, os, re, subprocess, sys
from datetime import date
from urllib.parse import urlsplit

HERE = os.path.dirname(os.path.abspath(__file__))
CAP = 25
MONTHS = {m: i + 1 for i, m in enumerate("jan feb mar apr may jun jul aug sep oct nov dec".split())}
MON = r"(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.?"
# hosts / title words that look like an official or primary record
OFFICIAL_HOST = re.compile(r"(\.gov(\.[a-z]{2})?$|\.mil$|\.int$|europa\.eu$|morh\.hr$|sabor\.hr$|predsjednik\.hr$|vlada\.hr$|soa\.hr$"
                           r"|hanfa\.hr$|nn\.hr$|\.parliament\.|\.gouv\.fr$|\.gob\.[a-z]{2}$|ofac|sanctionssearch|societe\.com$|pappers\.fr$"
                           r"|zse\.hr$|fina\.hr$|zakon\.hr$|sudreg|opencorporates\.com$|eur-lex)")
OFFICIAL_TITLE = re.compile(r"\b(ministry|MORH|decree|gazette|narodne novine|treasury|OFAC|state department|registry|SIREN|Act on|NN \d+/\d+)\b", re.I)


def dump(data_js):
    out = subprocess.run(["node", os.path.join(HERE, "dump_data.js"), data_js], capture_output=True, text=True)
    if out.returncode:
        sys.exit("could not load data.js:\n" + out.stderr)
    return json.loads(out.stdout)


def merged(D):
    """The graph as the page sees it (ENRICH applied). Copied from apply_patch.py."""
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


def src_date(title, url):
    """(date, how) for a source: end of the period named in the title, else a /YYYY/MM/ in the URL."""
    best = None
    def put(y, m=12, d=None):
        nonlocal best
        if not 1990 <= y <= date.today().year + 1 or not 1 <= m <= 12: return
        if d is None:  # month or year only: take the END of the period, so only clearly old sources are flagged
            d = 28 if m == 2 else 30 if m in (4, 6, 9, 11) else 31
        try: c = min(date(y, m, d), date.today())
        except ValueError: return
        best = max(best, c) if best else c
    t = title or ""
    # a bare year must stand alone ('HS-2000', 'Decree 2016-1616' are names, not dates)
    # most precise form wins: a full date, else month+year, else a bare year (so "9 Oct 2026" is not read as Dec 2026)
    for y, m, d in re.findall(r"\b(\d{4})-(\d\d)-(\d\d)\b", t): put(int(y), int(m), int(d))
    for d, m, y in re.findall(r"\b(\d{1,2})\s+" + MON + r"\s+(\d{4})\b", t, re.I): put(int(y), MONTHS[m[:3].lower()], int(d))
    if not best:
        for m, y in re.findall(r"\b" + MON + r"\s+(\d{4})\b", t, re.I): put(int(y), MONTHS[m[:3].lower()])
    if not best:
        for y in re.findall(r"(?<![-/\w])((?:19|20)\d\d)(?![-/\w])", t): put(int(y))
    if best: return best, "title"
    u = re.search(r"/((?:19|20)\d\d)/(\d\d)(?:/(\d\d))?(?:/|$)", url or "")
    if u:
        put(int(u.group(1)), int(u.group(2)), int(u.group(3)) if u.group(3) else None)
        if best: return best, "url"
    u = re.search(r"/((?:19|20)\d\d)(\d\d)(\d\d)\d*", url or "")  # e.g. /en/202610181490
    if u:
        put(int(u.group(1)), int(u.group(2)), int(u.group(3)))
        if best: return best, "url"
    return None, None


def src_class(title, url):
    """official / wiki / other (press, vendor, blog), judged from the host and title wording."""
    host = (urlsplit(url or "").hostname or "").lower().removeprefix("www.")
    if "wikipedia.org" in host or "wikidata" in host: return "wiki"
    if OFFICIAL_HOST.search(host) or OFFICIAL_TITLE.search(title or ""): return "official"
    return "other"


def own_site(url, *names):
    """True when the source's site name (e.g. koncar.hr -> 'koncar') shows up in a linked entity's id/label/short: the party's own statement."""
    host = (urlsplit(url or "").hostname or "").lower().removeprefix("www.").split(".")
    key = host[-2] if len(host) > 1 else ""
    return len(key) >= 4 and any(key in re.sub(r"[^a-z0-9]", "", (x or "").lower()) for x in names)


def norm_url(u):
    p = urlsplit((u or "").strip())
    return (p.hostname or "").removeprefix("www.") + p.path.rstrip("/") + ("?" + p.query if p.query else "")


def audit(D):
    src, rel, nodes, edges = merged(D)
    grades = list(D["CONF"])
    top, low = grades[0], grades[-1]
    today = date.today()
    info = {k: src_date(v[0], v[1]) for k, v in src.items()}
    cls = {k: src_class(v[0], v[1]) for k, v in src.items()}
    lab = lambda i: nodes[i].get("label", i) if i in nodes else i
    R = {"map": D["CONFIG"].get("title") if isinstance(D.get("CONFIG"), dict) else None,
         "today": today.isoformat(), "top_grade": top, "low_grade": low,
         "counts": {"entities": len(nodes), "links": len(edges), "sources": len(src)}}

    # a) newest source older than a year; entities with no dated source at all
    old, undated = [], []
    for i, n in nodes.items():
        ds = [(info[s][0], s) for s in n.get("src") or [] if s in info and info[s][0]]
        und = [s for s in n.get("src") or [] if s in info and not info[s][0]]
        if not ds:
            undated.append({"id": i, "label": lab(i), "sources": n.get("src") or [], "why": "no source carries a parseable date" if und else "no sources"})
        else:
            d, s = max(ds)
            if (today - d).days > 365:
                old.append({"id": i, "label": lab(i), "newest": d.isoformat(), "source": s, "age_days": (today - d).days, "undated_sources": len(und)})
    R["a_old"] = sorted(old, key=lambda r: -r["age_days"])
    R["a_undated"] = undated

    # b) weak: exactly one source, or only lowest-grade links / status unverified
    inc = {i: [] for i in nodes}
    for e in edges:
        for x in e[:2]:
            if x in inc: inc[x].append(e)
    one, lowg = [], []
    for i, n in nodes.items():
        ss = n.get("src") or []
        if len(ss) == 1:
            one.append({"id": i, "label": lab(i), "source": ss[0], "class": cls.get(ss[0]), "date": (info.get(ss[0], (None,))[0] or "")and info[ss[0]][0].isoformat()})
        es = inc[i]
        if n.get("status") == "unverified" or (es and all(e[3] == low for e in es)):
            lowg.append({"id": i, "label": lab(i), "status": n.get("status"), "links": len(es),
                         "why": "status unverified" if n.get("status") == "unverified" else f"all {len(es)} link(s) graded '{low}'"})
    R["b_single_source"], R["b_low_grade"] = one, lowg

    # c) orphans
    R["c_orphans"] = [{"id": i, "label": lab(i), "kind": n.get("kind")} for i, n in nodes.items() if not inc[i]]

    # d) links graded above what their sources support
    rev = []
    for e in edges:
        s, t, r, g, ss = e[0], e[1], e[2], e[3], e[4] if len(e) > 4 else []
        cs = [cls.get(k, "other") for k in ss]
        # a company's or agency's own site, about itself, is an acceptable primary source under most CONF 'doc' definitions
        own = [own_site(src[k][1], s, t, nodes.get(s, {}).get("label"), nodes.get(t, {}).get("label"), nodes.get(s, {}).get("short"), nodes.get(t, {}).get("short")) for k in ss if k in src]
        cs = ["self" if o and c == "other" else c for c, o in zip(cs, own)]
        why = None
        if g == top and not ss: why, pr = "top grade with no sources", 0
        elif g == top and "official" not in cs and "self" not in cs:
            why, pr = (f"'{top}' but {'its one source is' if len(ss) == 1 else 'all sources are'} {'/'.join(sorted(set(cs)))} (press, vendor or aggregator)"), 1
        elif g == top and "official" not in cs:
            why, pr = f"'{top}' rests on a party's own site only ({'one source' if len(ss) == 1 else str(len(ss)) + ' sources'}); fine for its own claims, weak for third-party facts", 2
        elif g == top and len(ss) == 1: why, pr = f"'{top}' resting on one source (looks official, confirm it states this link)", 3
        elif g != top and g != low and ss and all(c == "wiki" for c in cs): why, pr = f"'{g}' but only Wikipedia cited", 4
        if why: rev.append({"from": s, "to": t, "rel": r, "grade": g, "sources": ss, "label": f"{lab(s)} -> {lab(t)}", "review": why, "priority": pr})
    R["d_links"] = sorted(rev, key=lambda r: r["priority"])

    # e) look-alike entities, duplicate URLs, dangling source keys
    by = {}
    for i, n in nodes.items():
        for f in ("label", "short"):
            k = norm(n.get(f))
            if k: by.setdefault(k, set()).add(i)
    R["e_entities"] = [{"norm": k, "ids": sorted(v), "labels": [lab(i) for i in sorted(v)]} for k, v in sorted(by.items()) if len(v) > 1]
    urls = {}
    for k, v in src.items(): urls.setdefault(norm_url(v[1]), []).append(k)
    R["e_sources"] = [{"url": u, "keys": sorted(v)} for u, v in sorted(urls.items()) if len(v) > 1]
    used = {s for n in nodes.values() for s in n.get("src") or []} | {s for e in edges for s in (e[4] if len(e) > 4 else [])}
    R["e_unknown_src"] = sorted(used - set(src))
    return R


def show(title, rows, fmt, note=""):
    print(f"\n== {title} ({len(rows)}) ==" + (f"\n   {note}" if note else ""))
    for r in rows[:CAP]: print("  " + fmt(r))
    if len(rows) > CAP: print(f"  +{len(rows) - CAP} more")


def text(R):
    c = R["counts"]
    print(f"AUDIT {R['map'] or ''} as of {R['today']}: {c['entities']} entities, {c['links']} links, {c['sources']} sources "
          f"(top grade '{R['top_grade']}', lowest '{R['low_grade']}')")
    show("a1. newest source older than a year", R["a_old"],
         lambda r: f"{r['id']:<22} {r['newest']}  ({r['age_days'] // 365}y {r['age_days'] % 365 // 30}m)  via {r['source']}" + (f"  [+{r['undated_sources']} undated src]" if r["undated_sources"] else ""),
         "dates from the source title (month/year-only read as end of period), else the URL")
    show("a2. undated: no source with a parseable date", R["a_undated"], lambda r: f"{r['id']:<22} {r['why']}: {', '.join(r['sources'][:4])}")
    show("b1. resting on a single source", R["b_single_source"],
         lambda r: f"{r['id']:<22} {r['source']} [{r['class']}{', ' + r['date'] if r['date'] else ''}]")
    show(f"b2. low-grade ('{R['low_grade']}') only or status unverified", R["b_low_grade"], lambda r: f"{r['id']:<22} {r['why']}")
    show("c. orphans (no links)", R["c_orphans"], lambda r: f"{r['id']:<22} {r['kind']}  {r['label']}")
    show(f"d. REVIEW links graded above their sources (top grade '{R['top_grade']}')", R["d_links"],
         lambda r: f"{r['from']} -[{r['rel']}]-> {r['to']} ({r['grade']}; {','.join(r['sources'])}): {r['review']}",
         "heuristic: official-looking = gov/mil/int hosts or ministry/decree/registry wording in the title")
    show("e1. look-alike entities", R["e_entities"], lambda r: f"'{r['norm']}': {', '.join(r['ids'])}")
    show("e2. duplicate source URLs", R["e_sources"], lambda r: f"{', '.join(r['keys'])}  {r['url'][:70]}")
    if R["e_unknown_src"]: print("\nUNKNOWN source keys cited:", ", ".join(R["e_unknown_src"]))


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1: sys.exit(__doc__)
    R = audit(dump(os.path.join(os.path.expanduser(args[0]), "data", "data.js")))
    if "--json" in sys.argv: print(json.dumps(R, ensure_ascii=False, indent=1))
    else: text(R)


if __name__ == "__main__":
    main()
