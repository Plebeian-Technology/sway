---
lat:
  mode: explanation
---

# Why LlmSummaryCompletedView is laid out the way it is

Keeps only two pieces of state — the open/closed flags for the two dialogs — so each action button can open the dialog beside it; the editable summary and breakdown toggle each own their own state.

## Dropping the confirm-dialog intent when the screen goes busy

Drops the confirm-dialog intent when the screen goes busy, so it can't reopen after. `isRegenerating` can flip from someone else's run — the dialog used to reopen with a stale, paid Confirm.

## The status badge and provenance chip

Shows the real status: this view also draws a `skipped` row still holding an earlier summary, so "Skipped" (not a green "Ready") tells the operator the last regeneration was dropped.

Where the text came from sits beside the status badge, not only in the out-of-date header, since a pasted row can still be up to date — in the gap before the next pipeline comparison.

## LlmSummaryInFlightNotice sits above everything it describes

Sits above everything it describes, since this view also draws a queued/running row that still holds the last run's summary and drafts — nothing below should read as the new run's output.

`pasteOwnsSummaryRun` passed to it: two columns, two questions. `llmProvider` names who wrote the text; `pasteOwnsSummaryRun` names who owns the row, and only it says what the reclaim sweep will do with it. See [[docs/explanation/abandoned-run-reclaim.md|Reclaiming an abandoned summary run]] for the backend side ("Which writer owns a reclaimable row").

## LlmSummaryFailedReasonNotice sits above the editor

Sits above the editor since a failed row here never reaches the generate branch (the other reason-printing place). `hasDraft` reads `llm_summary`, not the published text below. See [[docs/explanation/bill-summary-published-vs-draft-box-bug.md|the published-vs-draft box bug]].

## LlmSummarySkippedRunNotice lives here now, not in the generate branch

A released regeneration keeps the last run's summary, so this view claims the `skipped` message instead of the generate branch, where it used to live unreachable. See [[docs/explanation/skipped-run-notice-copy.md|skipped-run-notice-copy.md]] for the full history.

## LlmSummaryPositionsErrorNotice sits directly above the positions list

Sits directly above the positions list so the reason and any missing positions read as one message — the list isn't always empty, since a failed run can keep an earlier run's drafts.

## LlmSummaryRegenerateConfirmDialog and the shell's inert wrapper

Closed while a regeneration is in flight, like its sibling. Being passed as `children` does NOT put this under the shell's `inert` wrapper: Radix portals dialog content to `document.body`.
