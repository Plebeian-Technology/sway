---
mode: explanation
summary: "Why ScoreUpdaterService wraps every recompute in one requires_new transaction, why broadcast_score_refresh is a public class method sending a ping rather than a payload, and why each score family is recomputed against a different scope and term."
status: agent-extracted
related: [docs/explanation/score-recompute-service-overview.md, docs/explanation/vote-triggered-score-jobs-design.md, docs/explanation/score-recompute-user-legislator-term-race.md]
---

<!-- vale Vale.Spelling = NO -->

# Why `ScoreUpdaterService` is built the way it is

`ScoreUpdaterService` updates every score affected by one user's vote.
When a `UserVote` is saved it queues `OnUserVoteUpdateScoresJob`, and that
job runs this service.

## Why every recompute happens inside one `requires_new` transaction

All the recalculating happens inside a single database transaction, and
every total is rebuilt from scratch out of the source tables (see
[the ScoreRecomputeService overview](score-recompute-service-overview.md))
instead of being nudged up or down. That combination means running the
whole service twice cannot double-count anything, and a failure partway
through undoes every table it had touched. `requires_new:` asks for an
explicit savepoint, which behaves correctly both when this service is
called from inside another transaction, and inside a spec that wraps each
example in one.

## Why `broadcast_score_refresh` is a public class method

`ScoreUpdaterService.broadcast_score_refresh` sends a "your scores
changed" ping over ActionCable rather than the numbers themselves, so the
browser asks the server for what it actually needs rather than trusting a
payload that could be stale by the time it renders. It's a public CLASS
method — not merely a private instance method — specifically so
`ReconcileUserDistrictsService` can send the exact same channel and
message rather than inventing its own duplicate broadcast. The private
instance method further down calls straight through to this same class
method, so vote-driven updates behave exactly as they always did.

## Why the broadcast fires only after the transaction commits

`#call` invokes `broadcast_score_refresh` only after the
`ApplicationRecord.transaction` block returns — never inside it. The ping
tells the browser to come back and re-fetch; firing it before the
transaction commits would risk telling the browser to fetch numbers that
aren't there yet if the transaction later rolled back.

## Why each score family uses a different scope and a different term

The three `ScoreRecomputeService` calls in `#call` each pick their term
and their audience differently, on purpose:

- **`recompute_user_legislator!`** files the user's own score against a
  legislator under whichever term was RUNNING when the bill happened
  (`LegislatorTerm.covering`, chosen from the bill's own date), not the
  legislator's current term — so a vote cast today on an old bill updates
  the OLD term's row. Rows on the user's side are never sealed shut. A
  legislator with no terms at all (a mayor or a governor) is skipped
  entirely, keeping it out of `LegislatorTerm.covering`, which treats a
  termless legislator as a caller's mistake rather than a valid case.
  `legislator_term.nil?` specifically means this person held no office on
  the day of the bill's vote — before their first term or after their
  last one ended — so it is not theirs to be scored on.
- **`recompute_legislator_district!`** only counts the voter's own
  constituents, so this vote moves the score for the voter's own
  legislators and nobody else's. It always uses the legislator's CURRENT
  term (`legislator.active_term`) — a single user vote never rewrites a
  legislator's score for a term that has already ended.
- **`recompute_legislator_locale!`** counts EVERY user in the legislator's
  locale, not only their own constituents, because this vote gets
  compared against how EVERY legislator in the locale voted on the same
  bill — so all of their locale scores move, not only the voter's own
  legislators'. Updating only the voter's own legislators would have left
  every other legislator's locale score too low until that legislator
  next cast a vote of their own. The price is one tally per legislator in
  the locale for each vote cast, which is acceptable here specifically
  because this runs in a background job and only one job per bill runs at
  a time.
