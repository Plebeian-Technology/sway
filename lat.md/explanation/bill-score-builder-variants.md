---
lat:
  mode: explanation
---

# Why BillScore has two to_builder methods

`#to_builder` and `#to_builder_with_user` differ ONLY in which districts they include, and that difference is deliberate:

- `#to_builder` sends every district and feeds the public bill page
  (through `Bill#render`), so a signed-out viewer, or one from a different
  locale, still sees the whole district breakdown.
- `#to_builder_with_user` narrows the districts down to the viewer's own
  and feeds the personalized screens (`bills#index` and
  `BillScoresController#show`).

Every field that is not about districts must stay identical between the two.

## Why to_builder_with_user accepts a precomputed user_districts list

`#to_builder_with_user(user, user_districts: nil)` lets a caller hand in a districts list it already worked out, so a page listing many bills works out the user's districts once rather than once per bill.

Callers that do not supply one (the single bill page) get them computed inside the method instead.

## Why BillsController.index preloads bill_score_districts

`BillsController#index`'s `.includes({bill_score: {bill_score_districts: :district}})` exists so `#to_builder_with_user`'s per-district filter and nested district serialization do not run a query once per bill or district row.

`BillsController#index`'s `.includes({bill_score: {bill_score_districts: :district}})` is the counterpart to the precomputed `user_districts` list above: `#to_builder_with_user` compares `district_id` against `user_districts` before touching the preloaded `district` record, avoiding both per-bill score queries and per-district association loads.
