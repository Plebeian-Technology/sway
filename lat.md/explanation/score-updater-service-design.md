---
lat:
  mode: explanation
---

# Why ScoreUpdaterService is built the way it is

`ScoreUpdaterService` updates every score affected by one user's vote. When a `UserVote` is saved it queues `OnUserVoteUpdateScoresJob`, and that job runs this service.

## Why every recompute happens inside one requires_new transaction

The bill, user-legislator and locale recalculating happens inside a single database transaction, and every total is rebuilt from scratch out of the source tables (see [[docs/explanation/score-recompute-service-overview.md|the ScoreRecomputeService overview]]) instead of being nudged up or down.

That combination means running the whole service twice cannot double-count anything, and a failure partway through undoes every table it had touched. `requires_new:` asks for an explicit savepoint, which behaves correctly both when this service is called from inside another transaction, and inside a spec that wraps each example in one. The district scores are the exception: they run in a queued job after the transaction commits, so a failure in the job leaves the transaction's writes in place.

## Why broadcast_score_refresh is a public class method

`ScoreUpdaterService.broadcast_score_refresh` sends a "your scores changed" ping over ActionCable rather than the numbers themselves.

`ScoreUpdaterService.broadcast_score_refresh` sends a "your scores changed" ping over ActionCable rather than the numbers themselves, so the browser asks the server for what it actually needs rather than trusting a payload that could be stale by the time it renders. It's a public CLASS method — not merely a private instance method — specifically so `ReconcileUserDistrictsService` can send the exact same channel and message rather than inventing its own duplicate broadcast. The private instance method further down calls straight through to this same class method, so vote-driven updates behave exactly as they always did.

## Why the broadcast fires only after the transaction commits

`#call` invokes `broadcast_score_refresh` only after the `ApplicationRecord.transaction` block returns — never inside it.

The ping tells the browser to come back and re-fetch; firing it before the transaction commits would risk telling the browser to fetch numbers that aren't there yet if the transaction later rolled back.

## Why each score family uses a different scope and a different term

The three `ScoreRecomputeService` calls in `#call` each pick their term and their audience differently, on purpose:

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
- **`recompute_legislator_district!`** counts only a legislator's own
  constituents, but whether it may count a bill depends on the voters
  outside that district too
  ([[voter-privacy-threshold#Legislator scores count only bills that reached the minimum]]).
  One vote can therefore admit or drop the bill for a district the voter
  does not live in, so `recompute_district_scores!` in
  [[app/services/score_recompute_service.rb#ScoreRecomputeService]]
  recomputes the voter's own legislators and every legislator serving a
  district with a tally row on the bill. That is at most one tally per
  legislator in the locale, the price the locale scores already pay. It
  always uses the legislator's CURRENT term: a single user vote never
  rewrites a legislator's score for a term that has already ended. The
  vote, address-change and registration paths run it through
  [[app/jobs/recompute_district_scores_job.rb#RecomputeDistrictScoresJob]],
  because the method visits every legislator with a tally on the bill and
  holds SQLite's single write lock while it does. The vote path enqueues
  the job after its own transaction commits, so one vote on a Congress
  bill never keeps that lock for a few hundred district scores; the
  address-change and registration paths enqueue it for the bills the user
  voted on. The district scores therefore trail the vote by one queued
  job. The job receives bill and legislator ids, not records. The
  reconcile service already runs inside a job and calls the method
  inline.
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
