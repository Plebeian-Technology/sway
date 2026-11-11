---
lat:
  mode: explanation
---

# Why BillCreatorLlmSummaryStatus branches by content, not status alone

Branches by WHAT IS ON THE ROW, not status alone: any row still holding a summary or drafts goes to `LlmSummaryCompletedView`, so it always draws the real status badge, never a false "Ready".

## One busy flag for both regenerate buttons

Both regenerate buttons post to the same endpoint now, so one busy flag covers the panel — before, the header's `/regenerate_summary` button showed no busy state at all.

## Which statuses route to the completed view

`skipped`/`failed`/`pending`/`generating` can all still hold the last run's summary or drafts, so they route to the completed view too — only that view draws the real status badge.

`hasDraftSummary` reads `llm_summary`, the model's draft — never `bills.summary`, the published text (its own prop, written by no run). See [[docs/explanation/bill-summary-published-vs-draft-box-bug.md|the published-vs-draft box bug]].

## abandoned: derived once above the branch split

The server's judgement that nothing is writing to this row, derived once above the branch split. Used to be read only in the generating panel, leaving every other exit dead for a stuck row. See [[docs/explanation/abandoned-run-reclaim.md|Reclaiming an abandoned summary run]].

`shellProps.abandoned` is the only regenerate button on a stale row. Greys out on "queued or running", exactly what an abandoned row looks like but isn't.

`abandoned` is told separately from `isRegenerating`/`runInFlight` to `LlmSummaryCompletedView`, because it changes what the panel SAYS rather than what it allows: an abandoned row must not go on promising a run that is not coming.

## runInFlight: kept out of shellProps on purpose

A queued/running row must not offer a second paid run. Kept out of `shellProps`: the shell's copy covers the whole panel, hiding the content this branch exists to show.

`runInFlight` passed to `LlmSummaryCompletedView` gates Approve, not the regenerate buttons: switches off publishing an org position on drafts the queued run replaces. Not relaxed for abandoned: the server refuses regardless. See [[docs/explanation/org-position-approval-guard-chain.md|The approval guard chain]].

`isRegenerating` passed to `LlmSummaryCompletedView`: a queued/running row counts as busy, switching off Regenerate — else its operator could buy a second run. `&& !abandoned`: a reclaimable row has no writer to protect, and this is its only exit.

### Two runs can make a row busy, not one

`runInFlight` is the OR of two separate facts, and the second was missing until a code review caught it.

`summaryRunInFlight` reads `generation_status`, which belongs to the LLM summary job. It says nothing about `Testimony::CleanAndGroupService`, which never touches that column — so a clean-testimony run left this flag false while it rewrote the bill's cleaned artifact, the very `groups` array Approve reads, out from under an in-flight approval. That is the same hazard a second summary run poses, arriving by a column nobody was watching.

`cleanTestimonyRunning` closes it by reading the active pipeline run's own status. The `bill_id === null` half of the check is not defensive coding: the all-bills clean-testimony run carries no bill id, and rewrites this bill's artifact just as a single-bill run does.

This is the client-side fast path only. `ApproveOrgPositionService#run_in_flight?` enforces the same rule server-side, checked before the transaction and again under the write lock.

## Only an empty generating row reaches the second branch

Only an EMPTY generating row reaches here — one holding work took the branch above, which is also what lets the fall-through type-check below.

Used to have no way out: a stuck `generating` row with no earlier summary drew an always-disabled button. The sweep now publishes `reclaimable`, giving this button a real exit.

An empty pending row lands here; a worker dying before `mark_generating!` leaves one stuck forever. This branch used to shut its button on `isPending` alone, say nothing, with no exit.

## Two disabled reasons stay separate all the way down

The two reasons stay separate all the way down: merging them into one disabled flag would grey out the button without saying why, which is exactly what its `aria-describedby` needs.

## onConfirmRegenerate: one endpoint for both audit paths

Used to post to `/generate_summary`, whose service only logged the audit entry `if @regenerate` — so the common case spent LLM money with no Activity Log trace. Both buttons now share one endpoint. See [[docs/explanation/generate-bill-summary-service-concurrency.md|GenerateBillSummaryService concurrency]].
