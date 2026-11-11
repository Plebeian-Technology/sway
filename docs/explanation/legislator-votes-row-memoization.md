---
mode: explanation
summary: "Why BillCreatorLegislatorVotesRow is wrapped in React.memo."
status: agent-extracted
related: []
---

# Why `BillCreatorLegislatorVotesRow` is wrapped in `memo`

There is one of these per legislator in a long list, so it should only
redraw when its own props change.
