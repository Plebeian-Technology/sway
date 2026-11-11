---
mode: explanation
summary: "Why production_chain_smoke_spec.rb exists as a narrow early gate, and what its vote-identity comparison protects instead of the raw row count."
status: agent-extracted
related: [production-snapshot-deploy-rehearsal-harness, production-migration-spec-design]
---

# Production chain smoke spec design

`spec/production_readiness/production_chain_smoke_spec.rb` is a small
early check that the migrations apply cleanly to a fresh copy of the real
production database. `ProductionSnapshot.migrate!` runs the schema
migrations and the `db/data` migrations together, ordered by timestamp.
The real data is what makes this worth running: groups of
Congress legislators that share a `(sway_locale, external_id)` pair, plus
the McCormick pair left behind by redistricting.

## Why it stays narrow

It does not run the heavier identity, vote and passkey checks in
`spec/production_readiness/production_migration_spec.rb`, which still
query the old `legislators.district_id` column and so cannot pass once
this migration chain has run — rewriting those is separate work. This
spec only shows that the chain itself is safe against real data.

A snapshot taken after a deploy has nothing left to replay, so this
reports "did not run" instead of "broke" — see
[production_migration_spec's own note on the same situation](production-migration-spec-design.md#why-a-caught-up-snapshot-skips-instead-of-fails).

## What the vote-identity comparison actually protects

The spec collects every roll-call vote as `(bill, locale, person)` before
and after the migration — who voted on what, regardless of which
duplicate legislator row recorded it. How the locale is reached depends on
which shape the snapshot was taken in, and how a person is named depends
on whether the chain renames them; see `ProductionSnapshot.locale_reached_by`
and `.person_key_sql`.

The raw row count is deliberately not what is being protected. Duplicate
person rows each carry the same person's vote on the same bill, and the
migration has to fold them onto the one surviving person to satisfy the
existing unique index on `(bill_id, legislator_id)` from migration
`20260705000002`. What has to come through intact is the set of vote
identities — minus the rows the wrong-year cleanup deliberately
deletes; see `ProductionSnapshot.wrong_year_cleanup_exclusion`.
