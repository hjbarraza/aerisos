# Orbit popup: full-catalog mode — plan and ticket tracker

Goal: add "ALL ACTIVE" mode to the orbit popup (~/.config/quickshell/aeris-orbit) —
show every element-set-backed satellite (~15.9k), hover-highlight, click → info card +
personalized ground track. Keep the bright-sat O/H view as the unaffected default.

Measured (2026-11-01, Valencia):
- CelesTrak `active`: 15,898 objects, 2.6 MB TLE text, ~5 s fetch.
- Own propagator: dots for all 15.9k = 0.07 s; 1-object 281-pt track = 1 ms. Pure stdlib.
- Unmeasured risk: QML Canvas repainting 16k dots on the popup surface — benchmark live (T5).

Architecture decisions (amended after typesafe/jev-router review 2026-11-01):
- Catalog dots live in a SEPARATE file (/tmp/aeris-orbit-catalog.json, compact arrays
  [norad, name, lat, lon, lat1, lon1]) so the ~1.4 MB JSON-parse cost exists only while
  full mode is on. TLE cache: ~/.cache/aeris-catalog-tle.json, refreshed 12 h; on fetch
  failure the last good cache is kept and its age is published (`tleAge` h) in the payload
  so staleness is visible.
- Dots recompute every 5 MIN but the QML layer extrapolates each dot linearly from its
  own drift vector (no 90 s clamp) — curvature error over 5 min ≈ 1/2 px; 5 min of
  hard-stale dots would be ~2500 km wrong. Antimeridian crossing dashes a dot for one
  cycle; accepted.
- Selected-catalog-object info + track on demand via a want-file hop with REQUEST IDS:
  popup writes /tmp/aeris-orbit-want.json {req, norad}; daemon answers
  /tmp/aeris-orbit-selected.json {req, norad, info, track} or {req, norad, error}.
  QML renders a response only if resp.norad === catalogSel. Writes atomic (os.replace).
- /tmp stays as the IPC root (single-user box, same trust boundary as the existing
  shared tracks file — moving it would break the screensaver contract on the T2);
  new files written with mode 0600.
- QML scope: `catalogSel` (norad int) exclusively with `selected` (name) and `selLaunch`;
  selecting any clears the others. Selected object's track draws via the existing
  track-painting canvas (paints selData.track in warn white). Stations selector
  unaffected (keys only from orbit.tracks).
- Paint-cost probe: the catalog canvas logs `catalog paint N ms` only when a repaint
  exceeds 8 ms — objective numbers for the T6 benchmark without touching idle frames.
- Mode = CelesTrak ACTIVE catalog (15,898 payloads; debris/decayed excluded on purpose).

## Tickets

| # | Ticket | Status |
|---|---|---|
| T1 | Daemon: catalog cache + dots file (12 h TLE cache, 5 min dots, write only in full mode? cheap enough: always write while popup open) | [x] 874 KB, 15,871 dots; handles CelesTrak's 2-h freshness 403 by keeping the last good cache |
| T2 | Daemon: want-file watcher thread → selected-object info + track JSON | [x] req-id echoed; verified roundtrip with NORAD 25544 |
| T3 | QML: catalog file binding, toggle pill (right column, with live count) | [x] pill + "15871 · TLE 1 H" caption |
| T4 | QML: catalog Canvas dot layer, hover ring + label, click select / clear on empty map | [x] static canvas + 40 ms-throttled nearest-dot scan; per-paint ms probe (logs only >8 ms) |
| T5 | QML: catalog selection stamp + personal track drawn on the lines canvas | [x] warn-white track + warn ring; ✕ / re-click / Esc close |
| T6 | Verify: popup relaunch clean logs, hover/click flows, repaint smoothness benchmark, user acceptance | [~] backend + QML-load verified clean; interactive feel + paint numbers after user toggles |
| T7 | Collect: sync deployed files into ~/aerisos dotfiles (uncommitted) | [x] 2026-11-01 |
| T8 | (proposal) Group filter (STARLINK/GPS/…), name search — waiting for 15.9k-dot feel | — |

Round 2 (user-approved menu: group chips, search, altitude bands; plus drag-select
region + zoom/pan, incl. "redraw on zoom"):

| # | Ticket | Status |
|---|---|---|
| T9 | Group chips: daemon per-group caches (CelesTrak groups, 12 h, lazy) + groups.json; QML chip Flow selecting the dot source | [ ] |
| T10 | Name search: field in the filter row, substring scan over the active source, result rows replace the O/H list, click = select | [ ] |
| T11 | Altitude bands from mean motion (LOW <600 / MID <2k / MEO / GEO / HEO): daemon computes band per object, chips filter all sources | [ ] |
| T12 | Zoom (wheel, cursor-anchored, 1–24×) + pan (right-drag); base map, night mask and dot layer redraw via view change; Esc = clear, Esc×n | [ ] |
| T13 | Region select: left-drag rubber band → data-space rect; filters dots + hover + lists ("IN REGION N"); chip with ✕ | [ ] |
| T14 | Verify interactively (user), sync ~/aerisos | [ ] |

Launcher change: none (same daemon, richer duties).

Comment conventions: keep the terse file style; the owner wraps pollution escape hatches
in stdlib-only (no numpy) unless the benchmark says otherwise.
