---
lat:
  mode: explanation
---

# Why LlmSummaryGenerateBranch is shaped the way it is

Component branching structure isolating pending, failed, and unstarted summary states into a single unified workflow surface.

## TGenerateStatus excludes a summary-holding skipped row

`skipped` only arrives here with no earlier summary — one still holding `llm_summary` goes to the completed view instead.

## billId is only for the paste fallback

Only the paste fallback needs this. The generate and retry button posts through the `onGenerate` callback the parent already owns.

## isBillPipelineRunning and isRegenerating stay separate

Used to be one `disabled` flag, greying the button without saying WHY — exactly what `aria-describedby` needs. Kept apart so a regeneration-disabled button doesn't point at the pipeline notice.

## abandoned

The server's judgement that a `pending` row has nothing writing to it. This branch used to shut its button on `isPending` alone, with no notice and no exit. See [[docs/explanation/abandoned-run-reclaim.md|Reclaiming an abandoned summary run]].

## hasTestimony

Only the abandoned notice reads it, to say what a new run buys.

## What a skipped row is told now lives elsewhere

What a skipped row is told now lives in `LlmSummarySkippedRunNotice` — used to be written inline here, unreachable for a released regeneration routed to the completed view.

## No "Pipeline error:" prefix

`generation_error` is a summary-run fact, never a pipeline error — the old prefix sent operators to re-run a paid pipeline for a fault it couldn't touch.

## Why the abandoned notice can assume "never started" here

An abandoned row reaching THIS branch is always `pending`, so the notice can say "never started" rather than "stopped part-way". See [[docs/explanation/llm-summary-notice-phrase-pairing.md|llm-summary-notice-phrase-pairing.md]].

## Why the queued notice is gated on !abandoned

The two notices make opposite claims — one says a run is coming, the other says nothing is working on this row — so `!abandoned` is what keeps them off the screen together.

## LlmSummarySkippedRunNotice's hasDraft is false by construction

`hasDraft` is false by construction: this branch is only reached when the row carries no summary and no drafts.

## The generate/retry button

The busy word and screen-reader rule moved into `SummaryRunButton`, which every start-a-run button on this screen now draws through. This one used to say nothing while its request was in flight. See [[docs/explanation/bill-summary-run-button-unification.md|bill-summary-run-button-unification.md]].

`disabled={(isPending && !abandoned) || isBillPipelineRunning}`: `isPending && !abandoned` — a queued row must not buy a second run, but an abandoned row only looks queued — this button is its ONLY exit.

## What LlmSummaryGenerateBranch.test.tsx tests

Tests only that the attachment-failure warning shows and renders before the field, for a bill that has never been summarized. Other branch behavior is covered in LlmSummaryStatusBranches.test.tsx.
