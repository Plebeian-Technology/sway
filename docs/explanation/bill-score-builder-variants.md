---
mode: explanation
summary: "Explains why BillScore has two separate to_builder methods differing only in which districts they include, and why to_builder_with_user accepts a precomputed user_districts list."
status: agent-extracted
related: []
---
<!-- vale Vale.Spelling = NO -->

# Why BillScore has two to_builder methods

`#to_builder` and `#to_builder_with_user` differ ONLY in which districts
they include, and that difference is deliberate:

- `#to_builder` sends every district and feeds the public bill page
  (through `Bill#render`), so a signed-out viewer, or one from a different
  locale, still sees the whole district breakdown.
- `#to_builder_with_user` narrows the districts down to the viewer's own
  and feeds the personalized screens (`bills#index` and
  `BillScoresController#show`).

Every field that is not about districts must stay identical between the
two.

## Why to_builder_with_user accepts a precomputed user_districts list

`#to_builder_with_user(user, user_districts: nil)` lets a caller hand in a
districts list it already worked out, so a page listing many bills works
out the user's districts once rather than once per bill. Callers that do
not supply one (the single bill page) get them computed inside the
method instead.

## Why `BillsController#index` preloads `bill_score_districts`

`bills_index_scope`'s `.includes({bill_score: :bill_score_districts})`
exists so `#to_builder_with_user`'s per-district filter does not run a
query once per bill — the counterpart to the precomputed
`user_districts` list above: one preload avoids the N+1 on the association
side, the other avoids re-deriving the district list on the caller side.
