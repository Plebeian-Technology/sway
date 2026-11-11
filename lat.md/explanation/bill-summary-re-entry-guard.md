---
lat:
  mode: explanation
---

# The re-entry gate in GenerateBillSummaryJob.perform

`retry_on TransientBillSummaryError` restarts `#perform` from the top.

A gate near the top of `#perform` asks "did a previous execution of THIS enqueue already pay for and persist a summary?" before the job makes any paid call. Without that gate, a single raise after the persist re-issued both paid adapter calls — up to 3 executions, meaning up to 3 summary calls plus 3 positions calls, for one operator click, against a spec constraint that is explicitly about LLM cost.

## Why one structural guard, not a rescue at each raise site

An earlier fix for this exact failure guarded exactly one raise site inside the danger window: `mark_completed!` raising `StateMachines::InvalidTransition` (see [[docs/explanation/bill-summary-settle-completed-guard.md|bill-summary-settle-completed-guard.md]]).

The window still contains `BillCategoryAssigner`'s `@bill.with_lock`, the `RecomputeBillInterestingScoreJob` enqueue (a write to the job-queue database, where the realistic failure is SQLite's `SQLITE_BUSY` — "another writer holds the lock"), `#settle_under_lock`'s own `with_lock`, and the catch-all rescue that converts every one of them to `TransientBillSummaryError`. Guarding raise sites one at a time is what left the window open before. The guard has to key on the ENQUEUE, not on which line raised.

## Why job_id, and not enqueued_at

`enqueued_at` is re-stamped on every retry (see the stale-job gate in `#perform`), so on attempt 2 it is NEWER than the `llm_generated_at` attempt 1 wrote.

`enqueued_at` is re-stamped on every retry (see the stale-job gate in `#perform`), so on attempt 2 it is NEWER than the `llm_generated_at` attempt 1 wrote — the "is the summary newer than this enqueue?" comparison reads false exactly when it needs to read true.

`job_id` has the opposite, correct property: ActiveJob assigns it once at construction, serializes it with the job, restores it on deserialize, and `retry_job` re-enqueues the same instance. One operator click is one `job_id` no matter how many executions it takes, which is precisely "this enqueue."

The mechanism is named here, in this doc, rather than pinned to the Rails/ActiveJob gem's line numbers, because those line numbers move on every Rails patch release with nothing in this repository changing — nothing here or in CI would notice a drift. The claim is pinned instead by the spec example "`#perform` — re-entry after a post-persist failure does not re-buy" in `generate_bill_summary_job_spec.rb`, which hands a second job instance the first one's `job_id`, exactly what the queue does.

## Why summary_run_id carries the marker

Review found the `summary_run_id` column dead.

Review found the `summary_run_id` column dead: never written with a non-nil value anywhere, only cleared, and its original purpose (catching a late webhook from an earlier failed run) gone since the Python sidecar's summary webhook was removed. It is nonetheless exactly the right shape for this: a nullable string, uniquely indexed where non-null, cleared on every fresh generate by both this job and `GenerateBillSummaryService`, and named for the thing it now holds. Giving it a live meaning revives the dead column without a migration.

The write happens in the SAME `update!` that persists the summary, so "a summary was bought by this enqueue" and "the marker is set" cannot disagree — a raise between them is impossible.

Not short-circuited: a regenerate. That is a different `job_id`, so it pays again, which is what the operator asked for.

## What the marker does not say

The marker records that this enqueue spent money.

It does not say WHICH call the money bought, because both persist sites (the summary persist and the positions persist) write the same value. Treating a hit as "the run finished" was wrong for a bill with testimony: an execution that persisted the summary and then stopped before the positions call landed left the marker set and the positions half unbought, and a retry settled the row `completed` with no drafts on it. The purchase was never made and nothing would ever make it — there is no backfill for positions, and the operator's only lever is Regenerate, which re-buys the summary as well. That is exactly the double charge this gate exists to prevent.

### Simulating the crash: a raise inside the positions rescue's own recording write

The spec pinning "a failure between the summary persist and the positions persist" needs the positions call to fail in a way that escapes the positions rescue entirely and reaches the job's outer catch-all.

The spec pinning "a failure between the summary persist and the positions persist" needs the positions call to fail in a way that escapes the positions rescue entirely and reaches the job's outer catch-all, rather than being recorded and swallowed by that rescue. It gets there by stubbing `Sway::Utf8.scrub` to raise `ActiveRecord::StatementInvalid` (a simulated `SQLITE_BUSY`) specifically on the positions error message the rescue tries to record — so the raise happens INSIDE the rescue's own write, not the positions call itself. That failure is retried under the same enqueue and reaches the identical committed state (summary persisted, `summary_run_id` set, no positions) that a worker killed mid-call — a deploy landing, the Pi running out of memory — would reach with no exception raised anywhere at all. Both paths land the retry at the same row shape, which is what this gate has to handle either way.

The row itself answers the question the marker cannot, so the marker does not need to carry more: a bill with testimony and no persisted drafts is owed a positions call, whoever stopped and whenever. On that reading, the run resumes at the half it still owes and buys nothing it already has — see `#resumed_after_purchase?` and the `resume_positions_only` flag in `#perform`.

## settle_resumed_run: the same no-summary rule applies to the resumed path

`#settle_resumed_run` handles a retry that arrives with nothing left to buy.

Categories are deliberately NOT re-derived here: the response that carried them belongs to the execution that already ended, and paying for it again is the whole thing the re-entry gate exists to prevent. An uncategorized completed bill is `BackfillBillCategoriesJob`'s job to fix.

A row with NO summary on it may not settle `completed` here, for the same reason the two spend-gate settles in `#perform` exist: completed over a blank `llm_summary` is a green Ready badge that `#stale?` can never contradict (`llm_generated_at` is nil). This cheap exit used to skip that check, so a retry of a testimony-only run flipped the deliberate `failed` settle to `completed` and erased the stored reason on the way. It now routes to the same no-summary settle `#perform` would use: testimony present means the positions half is what this enqueue bought (`settle_no_source_text`); neither input means nothing was ever there (`settle_nothing_to_generate`). Both keep the marker on the row, so a THIRD arrival of this enqueue still takes this exit and still buys nothing — a regenerate (new `job_id`) clears the marker and pays, which is what the operator asked for.

`clear_generation_error: true` on the completed branch, because the previous attempt's `record_failure` wrote its wrapped message onto the row (and, doing so, already overwrote any note the positions rescue had left — that loss predates this gate). Carrying that message onto a COMPLETED row would break the rule `LlmSummaryPositionsErrorNotice` depends on: on a completed row, `generation_error` can only have come from the positions rescue.

### Pinning the third branch: settle_nothing_to_generate on a resumed run

`#settle_resumed_run` branches three ways, and for a while only two of them — `settle_completed` and `settle_no_source_text` — had a spec.

The third, `settle_nothing_to_generate`, is reachable through an ordinary sequence: a testimony-only run buys the positions half and stamps the purchase marker, then raises before settling (the same `SQLITE_BUSY` shape used to simulate a crash elsewhere in this file — see "Simulating the crash" above); in the gap before the retry, a `fetch_hearings` pipeline run reaches `:retract` and clears the testimony out from under it. The retry then lands in `#settle_resumed_run` on a row with drafts this very enqueue already paid for, but neither a summary nor any testimony left to justify one.

Which message that settle stores is a decision worth pinning on its own, not leaving to fall-through: the row holds no summary, so `failed` with a reason is the honest status, and the reason names the two things the operator can actually do about it — run the extract-text and fetch-hearings stages again, or paste testimony by hand. The drafts stay on the row through this settle: they are this enqueue's own purchase, and the no-summary settle must not discard them on the way past, even though it is reporting the run as failed.
