---
description: Situation brief from the AERISOS feeds (air, GNSS, space weather, outages, world news)
agent: AERIS
---
Produce a situation brief from the AERISOS status feed below. It is collected locally by the AERISOS status timer; times are local.

Structure:
1. **BLUF**: two or three sentences on what matters right now.
2. **Key judgments**: bullets with a confidence level each. Flag anything unusual: military or emergency air activity, GNSS interference, geomagnetic storms (Kp 5+ or G-scale above G0), radio blackouts, internet outages in notable countries, alerts.
3. **World**: the headlines grouped by theme, one line each, with the source.
4. **Gaps and next collection**: what the feed cannot tell us and what to check next. Offer to research any item in depth.

Treat feed values as reported, not verified. Do not invent figures that are not in the data.

Focus or extra tasking from the principal (may be empty): $ARGUMENTS

Feed:
!`python3 -c 'import json; d=json.load(open("/var/lib/aeris/status.json")); [d.pop(k, None) for k in ("identity", "state", "security", "local")]; d.get("net", {}).pop("lat", None); d.get("net", {}).pop("lon", None); d.get("net", {}).pop("coords", None); print(json.dumps(d, ensure_ascii=False, indent=1))'`
