---
description: Review watchlist changes, or manage the watchlist (e.g. /watch add Baltic GNSS jamming)
agent: AERIS
---
Watchlist tasking from the principal (may be empty): $ARGUMENTS

If the tasking asks to add, remove or change watched items, do it with `/home/h/.local/bin/aeris-watch` following the query rules in your instructions (OR groups, local-language feeds), check the new baseline, and confirm the resulting list.
Otherwise review what changed: assess the unreviewed findings below as leads (verify anything important before stating it as fact), brief the principal with a BLUF and one line per item that matters, recommend follow-up or new items to watch, then acknowledge the items you covered with `aeris-watch ack`.

Current watchlist:
!`/home/h/.local/bin/aeris-watch list --feeds`

Unreviewed findings:
!`/home/h/.local/bin/aeris-watch report`
