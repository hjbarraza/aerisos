---
description: The watchlist as an inbox - numbered list of this week's findings, then open items for detail (e.g. /inbox, then "open 3")
agent: AERIS
---
Inbox tasking from the principal (may be empty - then just present the inbox): $ARGUMENTS

Present the inbox below verbatim, then add at most two sentences: which topics dominate
and anything genuinely important for the standing questions. The list IS the brief.

Then triage on request:
- "open N": run `/home/h/.local/bin/aeris-inbox N` for topic, standing question, date and
  link; fetch the article (Google News links redirect - follow), summarize it in a few
  sentences against the topic's standing question, and say whether it advances it.
- "everything on <topic>": `/home/h/.local/bin/aeris-watch log <topic>`.
- "older": `/home/h/.local/bin/aeris-inbox --days 30`.
- Acknowledge reviewed topics with `/home/h/.local/bin/aeris-watch ack <topic>` (per
  topic, not per item; never ack what the principal has not seen).

Current inbox:
!`/home/h/.local/bin/aeris-inbox`
