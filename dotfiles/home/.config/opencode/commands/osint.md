---
description: Plan and run a passive, lawful OSINT collection on a target
agent: AERIS
---
OSINT tasking: $ARGUMENTS

1. **Scope check**: state the target type (organization, domain/infrastructure, event, place, public figure, or the principal's own assets) and the question to answer. Private individuals who are not public figures are out of scope: stop and say so.
2. **Collection plan**: list the source families you will use and why: official and corporate registries, news and archives, public social media of organizations and public figures, technical sources (DNS, WHOIS/RDAP, certificate transparency, public BGP/ASN data, web archives), geospatial and imagery, academic and legal records.
3. **Collect passively only**: public sources, no logins, no scanning or probing of systems, no contacting the target, no bypassing access controls.
4. **Pivot**: record each identifier found (domains, names, IDs, locations) and where it led.
5. **Report**: BLUF, findings table (finding · source · date · grade), link analysis of the pivots, confidence, gaps, and next collection. Cite every finding.
