---
lat:
  mode: explanation
---

# Why BillInterestingScoreCalculator is built this way

`BillInterestingScoreCalculator` scores how "interesting" a bill is, in plain Ruby with no outside calls.

It reads the bill's real votes (the ones not inferred from who sponsored it) plus the organization positions that are still active, turns each into a score using the weight and threshold constants on the class, and saves exactly one `BillInterestingScore` row per call. Disagreement carries the most weight. Rows are only ever inserted, never updated, so the history stays intact.

`BillInterestingScore` deliberately has no uniqueness rule on `bill_id`: several rows for one bill is the point, one per recalculation, none overwritten — the accumulating rows double as a trail an operator can debug a scoring change against.

## Signals depend on the jurisdiction, not on "is it a city"

Which signals apply depends on whether the jurisdiction says how each member voted, which the locale declares. That is read once up front, never re-checked per vote or per signal:

- **It does** — vote defection + vote abstention + org split + timeliness.
- **It does not** — org split + timeliness only.

Baltimore is the one Sway jurisdiction that does not: none of the 200 matters checked carried a roll-call, so its two vote terms are fixed at 0.0 and legislator votes are not even queried. Leaving them out is honest; pretending the vote was unanimous would not be. A city that did publish roll-calls would declare so and get the full signal set — the calculator asked the wrong question for years, framed as "is it a city" rather than "does this jurisdiction publish member votes."

## The ceiling is fixed, not relative to other bills

The raw score is divided by a fixed ceiling worked out from the weight constants, never by what other bills happen to score right now.

A bill's `normalized_score` therefore moves only when that bill's own signals move. Each signal formula already caps itself at its own weight, so the ceiling holds by construction.

## Why .theoretical_max is a public class method that takes the answer as an argument

`BillInterestingScoreCalculator.theoretical_max` is public.

`BillInterestingScoreCalculator.theoretical_max` is public, and takes `publishes_member_votes` as an argument rather than reading the bill's locale itself, because the bill picker recomputes the same normalized score again at READ time (for sorting and the live "close vote" badge) and the two computations must divide by the same ceiling. Both call sites ask the locale the same question — `SwayLocale::JurisdictionRules#publishes_member_votes` — and hand the answer here, rather than each independently re-deriving which ceiling applies.

## Why organization positions are counted through normalize_support, not an exact match

`#org_position_counts` runs every stored `support` value through `OrganizationBillPosition.normalize_support` before counting, rather than comparing it exactly against `FOR`/`AGAINST`.

The `support` column is not held to the `FOR`/`AGAINST`/`ABSTAIN` wording at the model level: the member-facing org positions flow (`Organizations::PositionsController` and its position-change history) deliberately stores the words the request sends — `"support"` and `"oppose"` — and its own request specs pin that (`spec/requests/organizations/positions_spec.rb`). Counting with an exact match against `FOR`/`AGAINST` therefore silently dropped those rows out of this signal, with no error anywhere. Every row is put through the model's `STANCE_TO_SUPPORT` mapping instead — the one place that translation lives — rather than each caller re-deriving it.

Forcing the wording at the model level (a validation, or a `before_validation` that rewrote `"support"`/`"oppose"` into `FOR`/`AGAINST` on save) was considered and rejected: it would rewrite what the member-facing flow actually stores and change how it tracks edits, which is a bigger change than fixing this one read-side signal calls for.

## Why timeliness_score is frozen at compute time, not recomputed live

How recent the bill is, frozen at the moment the score is computed.

It takes the latest of three dates — introduced, final House vote, final Senate vote — and fades that in a straight line to 0 once `TIMELINESS_WINDOW_DAYS` have passed. `introduced_date_time_utc` can never be null, so every bill has at least that date to work from. The lowest a bill can honestly land is a raw score of 0.0: introduced longer ago than the window, with no votes and no organization positions. A row still gets written for it. The bill picker works out a fresh value when it reads, for sorting and the live badge; the value stored here is only a record of what was true at compute time.

## Why Bill needs dependent: :delete_all on bill_interesting_scores

`bill_interesting_scores.bill_id` is a real foreign key, and the SQLite adapter runs with `PRAGMA foreign_keys = ON`.

Without `has_many :bill_interesting_scores, dependent: :delete_all` on `Bill`, `bill.destroy!` raises `ActiveRecord::InvalidForeignKey` for any bill that has a score row — and the start-up backfill scores every bill in the current session, so destroying a bill without the association option would break as soon as that backfill had run.
