---
mode: explanation
summary: "Why uniqueStableKeys' disambiguating counter could itself collide with a real key, and how that was reachable through draftOrgPositionKeys' fallback naming."
status: agent-extracted
related: []
---

# Why `uniqueStableKeys`' counter could collide with a real key

The counter this helper adds to repeats came out of the same pool of names it
was trying to keep apart. A second "A" became "A#1" — word for word the key
an entry whose own name IS the text "A#1" gets. So the helper whose whole job
is "no two keys alike" could hand out a duplicate.

This is reachable, not theoretical. With no `draft_token`,
`draftOrgPositionKeys` falls back to `${org_name} ${stance} ${summary}`, and an
organization name or a summary containing "#1" is ordinary English. A
duplicate key makes React match two cards to one element, which throws away
what the operator was typing — the very thing this helper was added to stop.
