#!/usr/bin/env python3
"""Orbit popup feed: the next launches worldwide (Launch Library 2, free, no key) with pad coordinates
-> /tmp/aeris-orbit-launches.json. LL2 allows ~15 requests/hour, so a file younger than 25 min is reused.
Runs once; the popup's launcher repeats it every 30 min while open."""
import json, os, sys, time, urllib.request

OUT = "/tmp/aeris-orbit-launches.json"
URL = "https://ll.thespacedevs.com/2.2.0/launch/upcoming/?limit=8&hide_recent_previous=true"

try:
    if time.time() - os.path.getmtime(OUT) < 25 * 60:
        sys.exit(0)
except OSError:
    pass
try:
    req = urllib.request.Request(URL, headers={"User-Agent": "aeris-orbit"})
    rows = json.load(urllib.request.urlopen(req, timeout=15))["results"]
except Exception as e:
    print("launches:", e, file=sys.stderr)
    sys.exit(0)   # keep the last good file

out = []
for r in rows:
    pad = r.get("pad") or {}
    name = r.get("name") or ""
    veh, _, mis = name.partition(" | ")
    try:
        lat, lon = float(pad["latitude"]), float(pad["longitude"])
    except (KeyError, TypeError, ValueError):
        lat = lon = None
    out.append({"net": r.get("net"), "ws": r.get("window_start"), "we": r.get("window_end"),
                "status": (r.get("status") or {}).get("abbrev"),
                "provider": (r.get("launch_service_provider") or {}).get("name"),
                "vehicle": veh, "mission": mis or veh, "pad": pad.get("name"),
                "loc": (pad.get("location") or {}).get("name"), "lat": lat, "lon": lon})
tmp = OUT + ".tmp"
json.dump({"ts": int(time.time()), "launches": out}, open(tmp, "w"))
os.replace(tmp, OUT)
