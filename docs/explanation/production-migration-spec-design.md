---
mode: explanation
summary: "Why production_migration_spec.rb skips instead of failing on a caught-up snapshot, what its dedup and Baltimore re-keying checks compare instead of raw counts, and the wrong-year vote carve-out its helper queries apply."
status: agent-extracted
related: [production-snapshot-deploy-rehearsal-harness, production-chain-smoke-spec-design, legislator-identity-value-design]
---

# production_migration_spec.rb design notes

`spec/production_readiness/production_migration_spec.rb` replays the full
migration chain against a copy of real production data (see
[Production snapshot: a deploy rehearsal harness](production-snapshot-deploy-rehearsal-harness.md))
and checks several distinct invariants. This covers the spec's own design
decisions that are not general facts about `ProductionSnapshot` itself.

## Why the vote/link/sponsor helper queries carve out wrong-year cleanup rows

`raw_vote_identities` builds every roll-call vote as a `(bill, person)`
pair before the migration, regardless of which duplicate legislator row
recorded it. It reads whichever shape the snapshot is in, and names the
person whichever way survives the chain — see
`ProductionSnapshot.locale_reached_by` and `.person_key_sql`.

One deliberate carve-out: the wrong-year cleanup (data migration
`20260804000001`) DELETES the congress-sourced rows on every Congress bill
that a wrong-year fetch touched, so those rows must not be promised
survival. While that cleanup is still pending on the snapshot, they are
left out of the before-set with the cleanup's own criterion;
`production_wrong_year_congress_votes_spec.rb` pins what happens to them.
Once the snapshot records the cleanup as applied, the carve-out vanishes
and the exact promise covers every row again.

## Why a caught-up snapshot skips instead of fails

A snapshot pulled just after a deploy has nothing left to replay, and
replaying nothing proves nothing. The spec skips rather than fails: a red
result here reads as "the migrations damaged the data" when it really
means "production has caught up with the repo." A skip still says the
check did not run, which is the thing an earlier, always-passing assertion
here failed to protect against.

## Why the legislator dedup check compares facts, not the raw row count

After the chain runs, one legislator row exists per `(locale, external_id)`
pair, which is the new unique key, with every vote, representative link
and sponsorship still present. What is compared is the set of facts, not
the raw row count: the real production data holds duplicate votes by
the same person on the same bill, and those correctly collapse under the
existing unique index on `(bill_id, legislator_id)`.

## Why the Baltimore re-key admission check is narrow

The seat re-keying covers Baltimore, the one locale whose roster names SEATS
rather than people: `"baltimore-district-1"` becomes
`"baltimore-district-1|mark-parker"`, so two occupants of one seat can be
two rows and a successor can never be written over the previous occupant.
Those keys are new, and admitting them is narrow on purpose — a new key
still has to be in Baltimore AND be a key that already existed with a name
appended. Anything else is invented, which is what this check is for.

## Why the post-migration duplication check reads rows, not identities

Nothing is duplicated afterwards. The unique index on
`(bill_id, legislator_id)` already makes the first true in the database,
but the spec states it outright rather than trusting the index alone.

This asks the database which ROWS repeat, not which identities collapse.
Counting distinct identities instead would read a person held across two
terms as a duplicate: a spent
link to a Baltimore person's 2020 row sits beside a live link to the row
that person holds the seat under now, which is how `user_legislators`
keeps history and is exactly right.
