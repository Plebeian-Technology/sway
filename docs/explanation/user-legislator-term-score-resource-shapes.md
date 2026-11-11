---
mode: explanation
summary: "Why UserLegislatorTermScoreResource's current-term and lifetime shapes share the same nested key names."
status: agent-extracted
related: []
---

<!-- vale Vale.Spelling = NO -->

# Why the current-term and lifetime shapes share key names

`UserLegislatorTermScoreResource` returns how often a user agrees with a
legislator, over two spans: `.new(user_legislator_term_score).serializable_hash`
for the CURRENT term's numbers (keys matching the retired
`UserLegislatorScore#to_builder`), and `.lifetime_hash_for(user_legislator)`
for the sum across every term, computed fresh on each read — deliberately
no cache table.

The lifetime shape uses the same nested key names as the current-term shape
so `LegislatorChartsPanel` can render either one without branching on which
shape it received.

## The frontend type mirror (`app/frontend/index.d.ts`)

The same score, added up across every term the legislator served, worked
out when it is read (`UserLegislatorTermScoreResource.lifetime_hash_for`).
The inner keys match `user_legislator_score`, so the existing charts and
tiles work unchanged when the lifetime toggle is on.
