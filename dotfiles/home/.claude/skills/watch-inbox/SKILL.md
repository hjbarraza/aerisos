---
name: watch-inbox
description: Present the AERIS watchlist as an inbox for triage - a numbered list of this week's findings across all watched topics (companies like Helsing, Anduril, Palantir), then drill into single items on request, research them deeper, and acknowledge reviewed topics. Use when the user asks for their watchlist inbox, a watchlist brief, "what's new on the watchlist", or to go through watchlist items one by one.
---

# Watchlist inbox

The watchlist (managed by `~/.local/bin/aeris-watch`, data in
`~/.local/share/aeris/watchlist.json`) collects news findings per watched topic.
This skill presents them like an email inbox: list first, then open items on demand.

## 1. Show the inbox

Run `~/.local/bin/aeris-inbox` and show its output verbatim (it is already formatted:
numbered, newest first, `*` = unacknowledged). Add at most two sentences after it:
which topics dominate and anything that looks genuinely important for the user's
standing questions. Do not summarize every row - the list IS the brief.

## 2. Triage on request

- **"open N" / "more on N" / "what's behind 3"**: run `~/.local/bin/aeris-inbox N` to get
  the topic, its standing question (note), date and link. Fetch the link (Google News
  redirect URLs resolve to the article; follow the redirect). Summarize the article in a
  few sentences *against the topic's standing question*, and say whether it actually
  answers or advances it. Offer deeper research (web search) if it does.
- **"everything on <topic>"**: run `~/.local/bin/aeris-watch log <topic>` for the full
  history, or filter the inbox rows for that topic.
- **"older items"**: re-run with a wider window, e.g. `aeris-inbox --days 30`.

## 3. Acknowledge

`~/.local/bin/aeris-watch ack <topic>` marks a topic's findings as reviewed (moves
them to its archive); `ack --all` clears everything. Acknowledgement is per TOPIC,
not per item - say so if the user asks to ack a single row. After going through
items with the user, offer to ack the topics that were covered. Never ack topics
the user has not seen.

## 4. Managing the list

Adding or removing watched topics is `aeris-watch add/remove` - follow the query
conventions already in the list (`aeris-watch list --feeds`): quoted names for
generic words, OR-groups, one `add-feed` per extra language, a `--note` phrased as
the standing question the topic should answer.

Note: the lock screen and AERIS board read the same data, so acknowledgements
change what they show (acknowledged items still appear in the 7-day feed, without
the `*`).
