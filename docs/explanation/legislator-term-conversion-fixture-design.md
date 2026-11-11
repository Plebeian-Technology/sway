---
mode: explanation
summary: "Why the ConvertDuplicateLegislatorsToTerms spec rebuilds production's exact duplicate-row shapes as a fixture, and how it stays green across two later schema-cleanup migrations."
status: agent-extracted
related: [docs/explanation/testimony-classification-migration-dedup-bug.md]
---
<!-- vale Vale.Spelling = NO -->

# Why this migration spec's fixture is shaped the way it is

The `ConvertDuplicateLegislatorsToTerms` data migration converts
production's roughly 180 duplicate `(sway_locale, external_id)` Congress
legislator groups, plus the McCormick (external id `M001218`) GA6-to-GA7
redistricting pair, into first-class `legislator_terms` rows on one
canonical person per identity. The spec's fixture recreates the shape
production was actually in: one duplicate group of the common kind —
seeded three separate times (a May-2024 row belonging to the 118th
Congress, plus Jan-2025 and Aug-2025 rows that both belong to a single
119th term) — together with the McCormick pair, whose district moved when
the map was redrawn.

The examples check every behavior the migration promises: no duplicate
identities left afterward, each row filed under the right term, votes and
user-legislator links and sponsorships and cosponsorships still pointing
at the right person, `sway_locale_id` filled in, scores converted rather
than thrown away, and `user_districts` filled in.

## Staying green across two later cleanup migrations

Two later migrations (`db/migrate/20260711000010` and `...011`) drop the
old `legislators.district_id`/`active`/`title` columns, the
`legislator_id` column on `legislator_district_scores` and
`legislator_locale_scores`, and the `user_legislator_scores` table this
migration reads. Whichever of those columns or tables the current test
schema no longer has, the spec's `before(:all)`/`after(:all)` hooks add
back for the duration of the run — adding nothing when they are still
there — so the spec passes both before and after that schema change lands.

On a real deploy, those two clean-up migrations run strictly after this
data migration, but the test schema already has their results. So the
`before`/`after` blocks also undo the constraints they added, letting the
fixture recreate the true pre-conversion production shape: `NULL
sway_locale_id`, duplicate `(locale, external_id)` rows, and score rows
with no term. `after(:all)` puts them all back.

## Why a non-zero score on a losing row is saved with `validate: false`

A non-zero score on a row that loses the merge has to be re-derived onto
its term, never dropped. It's saved with `save!(validate: false)` because
the model now requires `legislator_term_id`, while a real pre-conversion
production row — the whole point of this fixture — carries only
`legislator_id` and knows nothing about terms.

## The two-generation same-term collision (newer `updated_at` wins)

A case found while smoke-testing production: the Jan-2025 and Aug-2025 rows
both map to one 119th-term, but each carries its own totals row, and only
one of them can hold the unique `legislator_term_id`. The one with the
newer `updated_at` must take the term slot; the older one is a snapshot
that has been superseded.

## The lone, never-duplicated legislator case

A legislator that was never duplicated — what the migration's own comment
calls "a lone, never-duplicated legislator", and by far the most common
case. Its `UserLegislator`'s old score is never touched by
`repoint_user_legislators`, which only runs for links to losing rows, so
the sweep that runs over everything has to pick it up instead.

## The same-user, same-term collision across two losing rows

A user linked to two losing rows inside the same duplicate group, both
filed under the same term. When the second one is repointed it finds the
first (already repointed in place) as its "duplicate", so both scores land
on one `(target, term)` `UserLegislatorTermScore` slot. They must be added
together, not one of them quietly dropped.

## Why the collision fixtures are created in id order

`@collision_user_a` and `@collision_user_b` are created in id order,
because `repoint_user_legislators` walks rows in primary-key order with
`find_each`. So `@collision_user_a` goes first (no duplicate yet, so it is
repointed in place), then `@collision_user_b`, which finds
`@collision_user_a` — now linked to the canonical row — as its "duplicate",
producing the collision.

## Why `find_or_create_by!` alone silently lost scores

`find_or_create_by!` runs its block only when it creates a row, so a user
linked to two losing rows in the same duplicate group (both filed under the
same term) quietly lost every score after the first — which is exactly the
"same person seeded several times and linked separately along the way"
case this migration exists to fix.
