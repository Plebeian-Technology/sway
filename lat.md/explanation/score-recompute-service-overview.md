---
lat:
  mode: explanation
---

# ScoreRecomputeService overview

`ScoreRecomputeService` is the one and only place that writes score totals: `BillScore`, `BillScoreDistrict`, `LegislatorDistrictScore`, `LegislatorLocaleScore`, and `UserLegislatorTermScore`.

## District score vs. locale score

`LegislatorLocaleScore` mirrors `LegislatorDistrictScore`'s columns; the two differ only in which users the aggregate is computed over.

`LegislatorDistrictScore` aggregates only users whose `UserLegislator` links to this legislator — district-bound users for district-bound legislators. `LegislatorLocaleScore` aggregates every user in the legislator's `SwayLocale` who has voted on bills the legislator voted on, regardless of district.

For at-large legislators (e.g. Mayor) the two aggregates are identical, but a `LegislatorLocaleScore` row is still maintained so the JSON shape stays uniform across every legislator.

## Term structure

Every score row belongs to a legislator's term of office.

The two legislator-side rows (`LegislatorDistrictScore` and `LegislatorLocaleScore`) are only ever recalculated for the term the caller hands in. The vote-triggered job hands in the current term; the recompute rake task and the seeder's rebuild hand in every term, ended ones included.

The user-side row (`UserLegislatorTermScore`) also belongs to a term, but it does keep changing. Someone can vote today on an old bill, and that updates the row for whichever term was running back then, because the caller picks the term from the bill's date (`LegislatorTerm.covering`) rather than from the legislator's current term.

`UserLegislatorScore` — the older, whole-career total, a single lifetime row a callback used to create automatically — is gone entirely, table and all: `ScoreRecomputeService` now writes the per-term `UserLegislatorTermScore` rows themselves instead, when they are needed. (This doc previously said the old table was merely read-only pending a follow-up removal; that follow-up has since happened. `UserLegislatorTermScore`'s own model comment made the same now-stale claim and has been corrected to point here.)

`UserLegislatorTermScore` counts agreement per TERM (one election cycle) rather than across the whole time a user has been connected to a legislator, specifically so a district change or a new election does not blur two different terms' records together into one number.

## The rebuild guarantee

Every method rebuilds totals from scratch out of the source tables (`user_votes` and `legislator_votes`) instead of adding or subtracting.

Running a recompute twice therefore lands on the same answer, and a retried background job cannot count anything twice. Rows are fetched with `create_or_find_by!` backed by unique database indexes, so two processes racing to create the same row end up on one row rather than splitting a total between two. (The one exception, `UserLegislatorTermScore`, is documented separately — see [[docs/explanation/score-recompute-user-legislator-term-race.md|the find_or_create_by! design decision]].)

The same `create_or_find_by!`-over-`create!` idiom, for the same race-avoidance reason, is why `Bill#create_default_bill_score` settles on the one `bill_scores` row the unique index on `bill_id` guarantees rather than racing another process also trying to create that bill's first score row. Callers wrap a related set of recomputes in one `ApplicationRecord.transaction`, so a failure part way through undoes every table.

Votes inferred rather than read — a sponsor is assumed to vote for their own bill — do count toward the agreement totals here. Only the "interesting score" engine leaves them out.

## Counting agreement: tally_agreement

`tally_agreement` pairs each of a set of users' votes with the legislator's vote on the same bill using a LEFT JOIN.

`tally_agreement` pairs each of a set of users' votes with the legislator's vote on the same bill using a LEFT JOIN, so bills the legislator never voted on still show up, with a blank on the legislator's side (counted as `no_legislator_vote` by `.classify`, not skipped).

Whether a bill falls inside the term is decided by `LegislatorTerm.covering` rather than by redoing the start-and-end-date arithmetic in this method. A bill it answers `nil` for fell when this person held no office — before their first term or after their last ended — and counts toward none of them. The covering term is resolved once per unique bill, not once per vote row, because `LegislatorTerm.covering` hits the database per call.

## Group scores carry a distinct voter count

District and locale scores go through `tally_group_agreement`, which drops bills under the ten-voter minimum and stores how many distinct users remain. [[voter-privacy-threshold#Legislator scores count only bills that reached the minimum]] gives the reason.

The column defaults to zero, so a row written before the column existed reads as hidden: alone it shows the placeholder, and in a lifetime sum it adds none of its counters ([[voter-privacy-threshold#A lifetime figure needs every summed term at the minimum]]). The deploy that adds the column therefore includes one run of `sway:scores:recompute_all`, which rewrites every term's row with its real count.

## Why recompute_legislator_locale! reads the locale off the legislator, not through districts

`recompute_legislator_locale!` finds who belongs to the locale from the `sway_locale_id` column on `Legislator` directly, rather than by joining through districts.

Going through districts instead would require every legislator to have a CURRENT term (a legislator between terms has no active district link) and would quietly leave out any user whose own legislator happens to be between terms — exactly the users a locale score is supposed to count.

## Why recompute_bill_score_districts! counts DISTINCT user_votes.id

The per-district tally counts `DISTINCT user_votes.id` rather than a plain count, because two of a user's active legislators can share a district — counting plainly would double-count that single user's vote for that district.

## Why .classify treats an abstention as neither agreement nor disagreement

`.classify` returns `:legislator_abstained`, and ONLY that, when the legislator's own vote was an abstention — deliberately not ALSO counted as a disagreement.

Older code bumped both counters at once. Sway users can only vote for or against, never abstain, so `user_support` itself is never an abstention; the abstain branch exists solely to describe what the LEGISLATOR did.
