---
lat:
  mode: explanation
---

# Why this migration spec's fixture is shaped the way it is

The `ConvertDuplicateLegislatorsToTerms` migration converts duplicate Congress legislator groups into terms on one person. The spec fixture recreates production's duplicate shape to verify that no records or scores are dropped.

The spec checks every behavior the migration promises: no duplicate identities left afterward, each row filed under the right term, votes and user-legislator links and sponsorships and cosponsorships still pointing at the right person, `sway_locale_id` filled in, scores converted rather than thrown away, and `user_districts` filled in.

## Staying green across two later cleanup migrations

Two later migrations drop deprecated legislator columns and legacy score tables. The spec before and after hooks temporarily restore missing schema elements and relax constraints so the fixture can recreate the pre-conversion production state.

On a real deploy, those two clean-up migrations run strictly after this data migration, but the test schema already has their results. The `before(:all)` and `after(:all)` blocks undo the constraints they added, letting the fixture recreate the true pre-conversion production shape: `NULL sway_locale_id`, duplicate `(locale, external_id)` rows, score rows with no term, and a legacy vote without `legislator_term_id`. `after(:all)` restores them when the spec finishes.

## Why a non-zero score on a losing row is saved with validate: false

A non-zero score on a losing row must be re-derived onto its term rather than dropped. It is saved with `validate: false` because the model requires `legislator_term_id`, but pre-conversion production rows carry only `legislator_id`.

## The two-generation same-term collision (newer updated_at wins)

When multiple duplicate rows map to a single term, only one score record can hold the unique `legislator_term_id`. The score row with the newer `updated_at` timestamp takes the term slot, superseding the older snapshot.

## The lone, never-duplicated legislator case

A legislator that was never duplicated is not touched by `repoint_user_legislators`, which only processes links to losing rows. The global conversion sweep must process these lone records to populate term-scoped scores.

## The same-user, same-term collision across two losing rows

When a user is linked to two losing rows in the same duplicate group that map to the same term, repointing causes both scores to target the same term slot. The scores must be summed together rather than dropped.

## Why the collision fixtures are created in id order

Collision fixtures are created in primary-key order because `repoint_user_legislators` iterates with `find_each`. The lower id link is repointed first, allowing the subsequent link to detect it as a duplicate and trigger collision merging.

## Why find_or_create_by! alone silently lost scores

`find_or_create_by!` executes its block only upon row creation. Using it alone silently discarded scores from subsequent duplicate links for the same user and term, motivating the migration's score summation logic.
