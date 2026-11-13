#!/bin/bash
# The screens' feed tables and right column (collector): a watch row splits into topic,
# telegram and unread, the topic only on its group's first row, a telegram that itself
# contains " · " stays whole; a news story's continuation lines carry no outlet, and only
# whole stories that fit are kept; the watchlist groups by topic; the right column leaves
# quiet values out and flags alerts.

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_python_test <<'PY'
import time
status = load_script("status/aeris-status")

cells = status.watch_cells([
    "* 12 NOV · ANDURIL · Drone deal · Latvia",
    "· 12 NOV · ANDURIL · Shipyard needs welders",
    "· 11 NOV · PALANTIR · Stock at $172",
    "· All quiet: 5 topics, 7 days",
])
assert_equal(cells[0], ("ANDURIL", "Drone deal · Latvia", True), "unread row keeps its whole telegram")
assert_equal(cells[1], ("", "Shipyard needs welders", False), "a repeated topic is left blank")
assert_equal(cells[2][0], "PALANTIR", "a new topic shows again")
assert_equal(cells[3], ("", "All quiet: 5 topics, 7 days", False), "a quiet line has no topic")

items = [{"source": "DEFENSENEWS.COM · 20:16"}, {"source": "THERECORD.MEDIA · 19:35"}, {"source": "X.COM · 19:00"}]
rows = status.news_cells([["· One"], ["· Two", "  continued"], ["· Three", "  more"]], items, 4)
assert_equal(rows, [("DEFENSENEWS", "One"), ("THERECORD", "Two"), ("", "continued")],
             "outlets lose their domain suffix, continuations are blank, a story that does not fit is dropped")

assert_equal(status._strip_topic("anduril: wins contract", "anduril"), "Wins contract", "a leading topic name goes")
assert_equal(status._strip_topic("Quantum Systems's new drone", "quantum-systems"), "Its new drone", "possessive becomes Its")

status._tg_down = True   # no model in tests: telegrams fall back to the title
day = time.strftime("%a, %d %b %Y %H:%M:%S GMT", time.gmtime())
def finds(n, word):
    words = ["harbour", "satellite", "contract", "funding", "factory", "missile", "software"]
    return [{"title": f"{word} {words[i]} {words[i]}{i}x", "date": day, "new": i == 0} for i in range(n)]
st = {"watch": {"items": [{"name": "alpha", "recent": finds(5, "Alpha")},
                          {"name": "beta", "recent": finds(5, "Beta")},
                          {"name": "gamma", "recent": finds(1, "Gamma")}]}}
wrows, more = status.watch_feed(st)
topics = [r.split(" · ")[1] for r in wrows]
assert_equal(len(wrows), status.WATCH_ROWS, "the watchlist fills its rows")
assert_equal((topics.count("ALPHA"), topics.count("BETA"), topics.count("GAMMA")), (4, 3, 1), "rows are shared out evenly")
assert_equal(topics, sorted(topics, key=topics.index), "rows are grouped by topic")
assert_equal(more, 11 - status.WATCH_ROWS, "stories left out are counted")

st = {"alerts": ["air.gnss"], "air": {"gnss": "JAMMED 4/9", "emergency": "NONE", "traffic": "8 AIRCRAFT", "fresh": "21:50"},
      "net": {"coords": "1° N  2° E", "fresh": "21:00 STALE"}, "local": {"utc": "+01:00"}, "space": {}, "world": {}}
side = status.side_rows(st)
values = [r.get("v") for r in side]
assert_equal(side[0], {"h": "LOCATION", "stale": True}, "a failed refresh flags the head")
assert_equal("1° N · 2° E" in values and not any("SQUAWK" in (v or "") for v in values), True, "no squawk row while quiet")
assert_equal(next(r for r in side if r.get("v") == "GNSS JAMMED 4/9")["a"], True, "jamming shows, inverted")
assert_equal(side[-1] != {}, True, "no trailing blank row")
PY
