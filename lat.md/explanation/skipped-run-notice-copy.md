---
lat:
  mode: explanation
---

# Why LlmSummarySkippedRunNotice reads the way it does

`LlmSummarySkippedRunNotice` explains why a `skipped` row was dropped, and it draws on BOTH views that can show one — the same shape `LlmSummaryAbandonedRunNotice` already took for the same problem.

## One copy, wherever it is offered

`BillCreatorLlmSummaryStatus` routes by what is ON the row, not by status: a row carrying an earlier summary or drafts goes to `LlmSummaryCompletedView`, and everything else goes to `LlmSummaryGenerateBranch`.

The notice used to live only inside the generate branch, so a released regeneration — the ordinary way to reach a stuck row, because release keeps the last run's text — showed a neutral "Skipped" badge, last week's summary, and no reason at all. All three consumers of `generation_error` on the completed view return null for `skipped`, so this was the one gap. See "Both arms need to reach a screen" in [[docs/explanation/summary-run-release-message-history.md|summary-run-release-message-history.md]] for the backend side of the same fix.

## Two ways to reach skipped, and they mean different things

The copy was static once, on the ground that no writer put a reason on a skipped row: `mark_stale_skipped!` wrote only the status transition, and every other writer of that column ended at `generating` or `failed`.

`SummaryRunRelease` is a writer that does supply a reason. The reclaim sweep frees a row nothing has written to for an hour, and on the `pending` arm it sets `generation_error` and then marks the row skipped. That row did not wait in a queue — a worker took it and died holding it. The notice prints whatever reason the row carries, and falls back to the queue-wait sentence only for the writer that carries nothing. See [[docs/reference/summary-run-release-message-invariants.md|summary-run-release-message-invariants.md]] for what each `SummaryRunRelease` message clause can and cannot prove.

Warning styling, not destructive: a released or passed-over run is not a failure, and the badge beside it already says "Skipped."

## No duration in the fallback

The fallback sentence used to read "longer than an hour" — a hand-copy of `GenerateBillSummaryJob::STALE_AFTER` written out by hand on a surface that cannot see the constant.

Changing that constant would leave the sentence false with every gate green. The operator's next step does not depend on the number, so the fallback drops it instead of hard-coding a value nothing enforces.

## No claim about who wrote the draft

The notice used to say a kept draft was "the model's draft from an earlier run," on the argument that `mark_skipped!` transitions only from `pending`.

That proves the draft body PREDATES this run; it does not prove a run produced it. `pending` is entered from `completed`, and a completed row's `llm_summary` can be an operator's own paste — `PasteSummaryService` writes the body — which a later Generate click supersedes by clearing the paste marker in the arming write. Release that row and the old wording called the operator's own hand-written text "the model's," from a run that never existed. The notice now says only that a draft summary is still on the bill, with no claim about who wrote it — the same rule and the same reason `LlmSummaryFailedReasonNotice` follows for its own `hasDraft` case.

`LlmSummaryFailedReasonNotice` makes no claim about which run wrote the draft either: `GenerateBillSummaryJob` commits `llm_summary` BEFORE it can fail, so the draft can be the very run that just failed.

### LlmSummaryFailedReasonNotice field and component notes

`hasDraft`: `llm_summary` is present — a draft EXISTS, not when/who wrote it. NOT the editor's text: that's `bills.summary`, written by no run.

Only `failed`: a completed row error belongs elsewhere (`LlmSummaryPositionsErrorNotice`), a skipped row to `LlmSummarySkippedRunNotice` — a skipped row can carry a reason too.

## Why mark_skipped only fires from pending

`BillLlmProvisioning`'s `generation_status` state machine only allows the `mark_skipped` event from `pending`.

A row that is already `generating` and then errors still ends at `failed`, never `skipped` — a job that was running had a real outcome to report, while one that never got the chance to run was overtaken rather than failed. `PipelineRunBill` and `PipelineRunStage` model the same distinction with the same step.

Marking a row `skipped` also releases the "already in progress" check `GenerateBillSummaryService` runs before it will queue a new job — that check treats `pending` and `generating` as still-live — so an operator can start the work again once the stranded row is marked `skipped` instead of being stuck watching a job that will never run.

The state machine's `initial:` is `nil` rather than `pending`, on purpose: older rows written before `generation_status` existed have no value in the column, and treating that as the same thing as a freshly queued row would show a "Queued" badge for a bill nothing ever queued.

## The STALE_AFTER skip is not a dead worker

A worker DID pick this up — `GenerateBillSummaryJob#perform` ran, hit `STALE_AFTER`, and called `mark_stale_skipped!` on purpose.

Wrong-cause copy sends operators hunting Solid Queue for a dead-worker fault that doesn't exist.

## The reclaim-sweep copy test notes (LlmSummaryStatusBranches.test.tsx)

`SummaryRunRelease`'s reclaim sweep now sets `generation_error` before marking a row skipped, so the earlier "always empty" claim no longer holds.

Two different causes reach `skipped` (STALE_AFTER timeout vs. a reclaim-sweep death), but the operator saw the same static text either way.

Mirrors `SummaryRunRelease::RELEASED_UNSTARTED_ERROR` (the `skipped` arm) — the old message covering both arms no longer exists.

Hand-copied server string — re-copy it whenever that constant moves, or it drifts silently out of sync.
