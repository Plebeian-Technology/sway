---
mode: explanation
summary: "Why SeedDevelopmentUserGraph's score-refresh methods are keyed by legislator term, and how it computes district membership without a stored table."
status: agent-extracted
related: [docs/explanation/score-recompute-service-overview.md]
---

# SeedDevelopmentUserGraph's own score-refresh pass

`SeedDevelopmentUserGraph` (`db/seeds/models/development_user_graph.rb`)
writes its own `LegislatorDistrictScore` and `UserLegislatorTermScore` rows
for the synthetic dev graph it builds, following the same term-keyed
conventions as `ScoreRecomputeService` (see
[the service overview](score-recompute-service-overview.md)) without calling
into that service.

## `refresh_legislator_district_scores!`

`LegislatorDistrictScore` is looked up by `legislator_term` alone — its
`legislator_id` column was dropped, and `legislator` now resolves read-only
through the term. Every legislator in this loop has an `active_term`,
because `all_locale_legislators` only finds legislators through the query
that joins on the active term.

## `refresh_user_legislator_scores!`

This writes `UserLegislatorTermScore`, which is scoped to a single
legislator term (the old `UserLegislatorScore`, which covered a legislator's
whole career, is retired). Rows are keyed on the legislator's CURRENT term,
mirroring `refresh_legislator_district_scores!` above. A legislator with no
active term has nothing to score against yet.

## Why the spec builds a `legislator_term` for every seeded legislator

A `Legislator`'s `title` and `district` now come from its `active_term`,
the `LegislatorTerm` whose dates cover today. `spec/seeds/seed_development_user_graph_spec.rb`
builds a matching `legislator_term` carrying the same district and title
for every legislator it creates — without one, the `.joins(:district)`
inside `all_locale_legislators` runs through `active_term`, drops the row,
and the seeder finds nothing to seed. `spec/support/setup.rb` needed the
same fix.

## `user_ids_by_district_id`

Which users belong to which district is computed live from ACTIVE
`user_legislators` rows (user -> legislator -> district) — the same source
the app itself uses (`User#districts`); a separate `user_districts` table no
longer exists. At-large districts appear as keys but are never read, because
`refresh_bill_score_districts!` only looks at `seedable_districts`.
