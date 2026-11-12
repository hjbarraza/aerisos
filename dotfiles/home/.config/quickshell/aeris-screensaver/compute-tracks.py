#!/usr/bin/env python3
"""Track computation for the orbit popup (and the screensaver): ISS/Tiangong ground tracks
and bright satellites, -> /tmp/aeris-screensaver-tracks.json. Runs as a daemon once the
popup opens (the launcher traps/kills it): rewrites the file every 60 s so the popup's
FileView watches pick up fresh data. Same mean-elements + J2 model as the status collector;
TLEs come from /var/lib/aeris caches (written hourly by aeris-status) with a direct
CelesTrak fallback. Stdlib only.
"""
import json, math, os, threading, time, urllib.request
from datetime import datetime, timezone

OUT = "/tmp/aeris-screensaver-tracks.json"
CATALOG_URL = "https://celestrak.org/NORAD/elements/gp.php?GROUP=active&FORMAT=TLE"
CATALOG_CACHE = os.path.expanduser("~/.cache/aeris-catalog-tle.json")   # {catalog:[[name,l1,l2]...]}
CATALOG_OUT = "/tmp/aeris-orbit-catalog.json"     # {ts, tleAge, objects:[[norad,name,lat,lon,lat1,lon1,band]...]}
WANT_IN = "/tmp/aeris-orbit-want.json"            # popup -> {req, norad}
SEL_OUT = "/tmp/aeris-orbit-selected.json"        # daemon -> {req, norad, name, info, track} | error
GROUPS = {"STARLINK": "starlink", "ONEWEB": "oneweb", "GPS": "gps-ops", "GLONASS": "glo-ops",
          "GALILEO": "galileo", "BEIDOU": "beidou", "IRIDIUM": "iridium-NEXT", "WEATHER": "weather",
          "MILITARY": "military"}
GROUPS_OUT = "/tmp/aeris-orbit-groups.json"       # {ts, groups:{NAME:[[norad,name,lat,lon,lat1,lon1,band]...]}}
BANDS = ("<600", "600-2K", "MEO", "GEO", "HEO")
TLE_CACHE = "/var/lib/aeris/tle-cache.json"      # {"ISS": [l1, l2], "CSS": [...] }
VISTLE_CACHE = "/var/lib/aeris/vistle-cache.json"  # {"sats": [[name, l1, l2], ...] }
OBS_LAT, OBS_LON = 39.47, -0.38                   # Valencia
STATION_TLE_URL = "https://celestrak.org/NORAD/elements/gp.php?GROUP=stations&FORMAT=TLE"
VISUAL_TLE_URL = "https://celestrak.org/NORAD/elements/gp.php?GROUP=visual&FORMAT=TLE"
STATIONS = {"ISS": "ISS (ZARYA)", "CSS": "CSS (TIANHE)"}

MU, RE, J2 = 398600.4418, 6378.137, 1.08262668e-3
WGS84_E2 = (1 / 298.257223563) * (2 - 1 / 298.257223563)
MAX_AGE = 25 * 3600          # caches are refreshed every 12 h by the collector


def fetch(url, timeout=10):
    return urllib.request.urlopen(urllib.request.Request(
        url, headers={"User-Agent": "aeris-orbit"}), timeout=timeout).read().decode()


def parse_tle_txt(txt):
    """name -> [l1, l2] from a CelesTrak TLE text dump."""
    lines = txt.splitlines()
    return {lines[i].strip(): [lines[i + 1], lines[i + 2]] for i in range(0, len(lines) - 2, 3)}


def stations_tles(now):
    try:
        if now - os.path.getmtime(TLE_CACHE) < MAX_AGE:
            d = json.load(open(TLE_CACHE))
            if "ISS" in d and "CSS" in d:
                return {k: d[k] for k in STATIONS}
    except Exception:
        pass
    t = parse_tle_txt(fetch(STATION_TLE_URL))
    return {k: t[n] for k, n in STATIONS.items() if n in t}


def visual_tles(now):
    try:
        if now - os.path.getmtime(VISTLE_CACHE) < MAX_AGE:
            return json.load(open(VISTLE_CACHE))
    except Exception:
        pass
    t = parse_tle_txt(fetch(VISUAL_TLE_URL))
    return {"sats": [[k, v[0], v[1]] for k, v in t.items()]}


def parse_tle(l1, l2):
    year, day = int(l1[18:20]), float(l1[20:32])
    epoch = datetime(2000 + year, 1, 1, tzinfo=timezone.utc).timestamp() + (day - 1) * 86400
    return {
        "epoch": epoch, "ndot2": float(l1[33:43]),
        "i": math.radians(float(l2[8:16])), "raan": math.radians(float(l2[17:25])),
        "e": float("0." + l2[26:33]), "argp": math.radians(float(l2[34:42])),
        "m": float(l2[43:51]), "n": float(l2[52:63]),
    }


def sat_ecef(s, t):
    dt = (t - s["epoch"]) / 86400
    n = (s["n"] + 2 * s["ndot2"] * dt) * 2 * math.pi / 86400
    a = (MU / n ** 2) ** (1 / 3)
    e, i = s["e"], s["i"]
    k = 1.5 * J2 * (RE / (a * (1 - e * e))) ** 2 * n * dt * 86400
    raan = s["raan"] - k * math.cos(i)
    argp = s["argp"] + k / 2 * (5 * math.cos(i) ** 2 - 1)
    m = math.radians(s["m"] + 360 * (s["n"] * dt + s["ndot2"] * dt * dt))
    ea = m
    for _ in range(6):
        ea -= (ea - e * math.sin(ea) - m) / (1 - e * math.cos(ea))
    xp, yp = a * (math.cos(ea) - e), a * math.sqrt(1 - e * e) * math.sin(ea)
    co, so, cw, sw, ci, si = math.cos(raan), math.sin(raan), math.cos(argp), math.sin(argp), math.cos(i), math.sin(i)
    x = (co * cw - so * sw * ci) * xp + (-co * sw - so * cw * ci) * yp
    y = (so * cw + co * sw * ci) * xp + (-so * sw + co * cw * ci) * yp
    z = sw * si * xp + cw * si * yp
    gmst = math.radians((280.46061837 + 360.98564736629 * (t / 86400 - 10957.5)) % 360)
    return x * math.cos(gmst) + y * math.sin(gmst), -x * math.sin(gmst) + y * math.cos(gmst), z


def observer(lat, lon):
    la, lo = math.radians(lat), math.radians(lon)
    nr = RE / math.sqrt(1 - WGS84_E2 * math.sin(la) ** 2)
    obs = (nr * math.cos(la) * math.cos(lo), nr * math.cos(la) * math.sin(lo), nr * (1 - WGS84_E2) * math.sin(la))
    up = (math.cos(la) * math.cos(lo), math.cos(la) * math.sin(lo), math.sin(la))
    return obs, up


def elevation(s, t, obs, up):
    d = [p - o for p, o in zip(sat_ecef(s, t), obs)]
    return math.degrees(math.asin(sum(a * b for a, b in zip(d, up)) / math.sqrt(sum(a * a for a in d))))


def subsat(s, t):
    """Geodetic latitude/longitude (deg) of the point below the satellite."""
    x, y, z = sat_ecef(s, t)
    lon = math.degrees(math.atan2(y, x))
    r_xy = math.hypot(x, y)
    lat = math.atan2(z, r_xy)
    for _ in range(6):      # ECEF -> geodetic (Newton on the latitude)
        n = RE / math.sqrt(1 - WGS84_E2 * math.sin(lat) ** 2)
        lat = math.atan((z + n * WGS84_E2 * math.sin(lat)) / r_xy)
    return math.degrees(lat), lon


TRACK_PAST, TRACK_AHEAD, STEP = 45 * 60, 95 * 60, 30  # seconds
CATALOG_TTL = 12 * 3600     # element-set refresh
DOTS_TTL = 5 * 60           # catalog dot recompute; QML extrapolates in between


def write_json(path, data):
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(data, f)
    os.chmod(tmp, 0o600)
    os.replace(tmp, path)


def catalog_cache(now):
    """[[name, l1, l2], ...] for the full active catalog; refreshes from CelesTrak when the
    cache passes 12 h. On fetch failure the last good cache is kept (any age) or raised if
    there never was one."""
    try:
        if now - os.path.getmtime(CATALOG_CACHE) < CATALOG_TTL:
            return json.load(open(CATALOG_CACHE))
    except Exception:
        pass
    try:
        entries = parse_tle_txt(fetch(CATALOG_URL, timeout=60))
    except Exception:
        if os.path.exists(CATALOG_CACHE):
            return json.load(open(CATALOG_CACHE))     # stale beats nothing
        raise
    data = {"_at": now, "catalog": [[n, v[0], v[1]] for n, v in entries.items()]}
    try:
        tmp = CATALOG_CACHE + ".tmp"
        with open(tmp, "w") as f:
            json.dump(data, f)
        os.replace(tmp, CATALOG_CACHE)
    except Exception:
        pass                                          # cache write is best-effort
    return data


def group_cache(now, key):
    """Group TLEs, same 12 h / 403-means-fresh rules as the catalog."""
    p = os.path.join(os.path.expanduser("~/.cache"), f"aeris-group-{key}.json")
    try:
        if now - os.path.getmtime(p) < CATALOG_TTL:
            return json.load(open(p))
    except Exception:
        pass
    try:
        entries = parse_tle_txt(fetch("https://celestrak.org/NORAD/elements/gp.php?"
                                      f"GROUP={key}&FORMAT=tle", timeout=30))
        data = [[n, v[0], v[1]] for n, v in entries.items()]
    except Exception:
        if os.path.exists(p):
            return json.load(open(p))                 # stale beats nothing
        return []                                     # group unavailable this cycle
    best_effort = data
    try:
        tmp = p + ".tmp"
        with open(tmp, "w") as f:
            json.dump(data, f)
        os.replace(tmp, p)
    except Exception:
        pass
    return data


def band_of(l2):
    """Orbit-family index from mean motion: 0 <600 km, 1 600-2k, 2 MEO, 3 GEO, 4 HEO/other."""
    n = float(l2[52:63])
    a = (MU / (n * 2 * math.pi / 86400) ** 2) ** (1 / 3) - RE
    return 0 if a < 600 else 1 if a < 2000 else 2 if a < 30000 else 3 if a < 45000 else 4


def dots(now, data):
    """[norad, name, position now, +60 s dead-reckon vector, orbit-family band] for one set."""
    objs = []
    for name, l1, l2 in data:
        try:
            s = parse_tle(l1, l2)
            lat, lon = subsat(s, now)
            lat1, lon1 = subsat(s, now + 60)
            objs.append([int(l1[2:7] or -1), name, round(lat, 2), round(lon, 2),
                         round(lat1, 2), round(lon1, 2), band_of(l2)])
        except Exception:
            continue
    return objs


def catalog_dots(now, data):
    return dots(now, data.get("catalog", []))


def select_service(want):
    """Info + personal ground track for one catalog object (popup's want-file request)."""
    now = time.time()
    norad = int(want["norad"])
    for name, l1, l2 in catalog_cache(now).get("catalog", []):
        if l1[2:7].strip() != str(norad):
            continue
        s = parse_tle(l1, l2)
        obs, up = observer(OBS_LAT, OBS_LON)
        info = describe(name, l1, s, now, obs, up)
        track, t = [], now - TRACK_PAST
        while t <= now + TRACK_AHEAD:
            lat, lon = subsat(s, t)
            track.append([round(t, 1), round(lat, 3), round(lon, 3)])
            t += STEP
        return {"req": want.get("req"), "norad": norad, "name": name, "ts": round(now, 1),
                "info": info, "track": track}
    return {"req": want.get("req"), "norad": norad, "error": "not in catalog"}


def select_watcher():                                 # thread: fast answers for the popup
    last = None
    while True:
        try:
            want = json.load(open(WANT_IN))
            if want.get("req") != last:
                last = want.get("req")
                write_json(SEL_OUT, select_service(want))   # atomic; keying keeps races shallow
        except FileNotFoundError:
            pass                                            # no request yet
        except Exception as e:
            print("select_watcher:", e, flush=True)
            time.sleep(2)
            continue
        time.sleep(0.4)


SAT_MIN_EL = 10.0       # same bar as the collector's OVERHEAD count


def describe(name, l1, s, now, obs, up):
    """TLE-derived detail for the popup's info panel: geometry at t = now."""
    x, y, z = sat_ecef(s, now)
    r = math.sqrt(x * x + y * y + z * z)
    d = [x - obs[0], y - obs[1], z - obs[2]]
    rng = math.sqrt(sum(c * c for c in d))
    la, lo = math.radians(OBS_LAT), math.radians(OBS_LON)
    east = (-math.sin(lo), math.cos(lo), 0.0)
    north = (-math.sin(la) * math.cos(lo), -math.sin(la) * math.sin(lo), math.cos(la))
    el = math.degrees(math.asin(sum(p * q for p, q in zip(d, up)) / rng))
    az = math.degrees(math.atan2(sum(p * q for p, q in zip(d, east)),
                                 sum(p * q for p, q in zip(d, north)))) % 360
    n = s["n"] + 2 * s["ndot2"] * (now - s["epoch"]) / 86400
    a = (MU / (n * 2 * math.pi / 86400) ** 2) ** (1 / 3)
    v = math.sqrt(MU * (2 / r - 1 / a))
    return {"norad": int(l1[2:7] or -1), "el": round(el), "az": round(az),
            "alt": round(r - RE), "vel": round(v, 2), "incl": round(math.degrees(s["i"]), 1),
            "period": round(1440 / s["n"], 1), "apo": round(a * (1 + s["e"]) - RE),
            "peri": round(a * (1 - s["e"]) - RE)}


def compute(now):
    obs, up = observer(OBS_LAT, OBS_LON)
    tracks, info = {}, {}
    for key, (l1, l2) in stations_tles(now).items():
        s = parse_tle(l1, l2)
        info[key] = describe(key, l1, s, now, obs, up)
        pts = []
        t = now - TRACK_PAST
        while t <= now + TRACK_AHEAD:
            lat, lon = subsat(s, t)
            pts.append([round(t, 1), round(lat, 3), round(lon, 3)])
            t += STEP
        tracks[key] = pts
    sats, seen = [], {}
    for name, l1, l2 in visual_tles(now).get("sats") or []:
        try:
            s = parse_tle(l1, l2)
            el = elevation(s, now, obs, up)
            if el < SAT_MIN_EL:
                continue
            name = name.split("(")[0].strip().title()
            seen[name] = seen.get(name, 0) + 1
            if seen[name] > 1:                      # title collision: disambiguate by NORAD id
                name = f"{name} {l1[2:7].strip()}"
            lat, lon = subsat(s, now)
            lat1, lon1 = subsat(s, now + 60)
            sats.append({"name": name, "el": round(el), "lat": round(lat, 2),
                         "lon": round(lon, 2), "lat1": round(lat1, 2), "lon1": round(lon1, 2)})
            info[name] = describe(name, l1, s, now, obs, up)
        except Exception:
            continue
    sats.sort(key=lambda s: s["el"], reverse=True)  # highest first, like the status board
    return {"ts": round(now, 1), "tracks": tracks, "sats": sats, "info": info}


def main():
    threading.Thread(target=select_watcher, daemon=True).start()
    cat_next, grp_next = 0, 0
    while True:
        now = time.time()
        try:
            write_json(OUT, compute(now))
        except Exception as e:
            print("compute-tracks:", e, flush=True)
        if now >= cat_next:                       # catalog dots, every 5 min (0.1 s of maths)
            try:
                data = catalog_cache(now)
                write_json(CATALOG_OUT, {"ts": round(now, 1),
                                         "tleAge": round((now - data.get("_at", now)) / 3600, 1),
                                         "objects": catalog_dots(now, data)})
                cat_next = now + DOTS_TTL
            except Exception as e:
                print("catalog:", e, flush=True)
                cat_next = now + 60               # retry in a minute; dots stay as-is
        if now >= grp_next:
            try:
                groups = {}
                for label, key in GROUPS.items():
                    cache = group_cache(now, key)
                    if cache:
                        groups[label] = dots(now, cache if isinstance(cache, list) else cache.get("catalog", []))
                write_json(GROUPS_OUT, {"ts": round(now, 1), "bands": BANDS, "groups": groups})
                grp_next = now + DOTS_TTL
            except Exception as e:
                print("groups:", e, flush=True)
                grp_next = now + 60
        time.sleep(60)


if __name__ == "__main__":
    main()
