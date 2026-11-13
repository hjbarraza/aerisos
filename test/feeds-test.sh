#!/bin/bash
# The lock screen's feed tables (watch_cells, news_cells in the collector): a watch row splits
# into mark, date, topic and telegram, the date only where it changes, a telegram that itself
# contains " · " stays whole; a news story's continuation lines carry no time or outlet, and
# only whole stories that fit are kept.

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_python_test <<'PY'
status = load_script("status/aeris-status")

cells = status.watch_cells([
    "* 12 NOV · ANDURIL · DRONE DEAL · LATVIA",
    "· 12 NOV · HELSING · AI PLATFORM",
    "· 11 NOV · PALANTIR · STOCK AT $172",
    "· ALL QUIET · 5 TOPICS · 7D",
])
assert_equal(cells[0], ("■", "12 NOV", "ANDURIL", "DRONE DEAL · LATVIA"), "unread row keeps its whole telegram")
assert_equal(cells[1], ("", "", "HELSING", "AI PLATFORM"), "a repeated date is left blank")
assert_equal(cells[2][1], "11 NOV", "a new date shows again")

items = [{"source": "DEFENSENEWS.COM · 20:16"}, {"source": "THERECORD.MEDIA · 19:35"}, {"source": "X.COM · 19:00"}]
rows = status.news_cells([["· ONE"], ["· TWO", "  CONTINUED"], ["· THREE", "  MORE"]], items, 4)
assert_equal(rows, [("20:16", "DEFENSENEWS", "ONE"), ("19:35", "THERECORD", "TWO"), ("", "", "CONTINUED")],
             "outlets lose their domain suffix, continuations are blank, a story that does not fit is dropped")
PY
