---
lat:
  mode: explanation
---

# Why the positions rescue absorbs every failure

Inside `GenerateBillSummaryJob#perform`, the block that makes the positions call is wrapped in a `begin`/`rescue`.

That rescue absorbs ANY failure of the positions block — it does not re-raise, and it does not wrap the error as `TransientBillSummaryError`. This choice was settled in review and is binding.

## Why a re-raise would be worse than the failure itself

`retry_on TransientBillSummaryError` restarts `#perform` from the top, so letting a positions failure escape would re-issue the SUMMARY call up to three times.

`retry_on TransientBillSummaryError` restarts `#perform` from the top, so letting a positions failure escape would re-issue the SUMMARY call up to three times — paying for the summary 3x against a spec constraint explicitly about LLM cost. And because `mark_completed!` runs after both calls, a re-raise here would strand a perfectly good summary in `failed`, which the Bill Creator renders as an error branch that never shows `llm_summary`.

## Why this differs from the summary call's error handling

The original review left `Llm::SchemaError` to the outer rescue ladder (the chain of rescue clauses at the bottom of `#perform`) on the theory that a malformed response is deterministic and deserves a discard.

That reasoning holds for the SUMMARY call (see [[docs/explanation/bill-summary-call-preconditions.md|bill-summary-call-preconditions.md]]) but flips here: by the time the positions call runs, the summary has ALREADY been paid for and persisted, so discarding on a positions schema error would destroy value that was bought rather than protect budget. `bill_positions.json` is also the stricter schema contract (`additionalProperties: false` at both levels), making it more likely than the summary schema to fail.

## Why the rescue catches StandardError, not just the Llm::* classes

This is the one call site in the job where that width is correct — the summary is already persisted and nothing downstream reads positions — and the narrow list was not merely theoretical.

An `ArgumentError` from a regexp over invalid UTF-8, and a `JSON::GeneratorError` from `serialize coder: JSON` on a model response carrying invalid bytes, both got past a narrower rescue and reached the catch-all. Nothing inside this region raises a `BillSummaryError`, so the outer ladder's handling of the SUMMARY call is untouched by this rescue's width.

## Recording the failure so the operator can see it

The failure is recorded in `generation_error` so the operator can see WHY positions are absent from an otherwise-complete summary.

That claim was false until the completed branch grew a place to show it: `generation_error` used to reach only `LlmSummaryGenerateBranch`, which a completed row never renders. `LlmSummaryPositionsErrorNotice` (rendered by `LlmSummaryCompletedView`) is now that place, and it relies on the rule that a COMPLETED row's `generation_error` can only have come from this rescue.

### The rule was asserted but not enforced

Review found three ways through it. The two server-side holes:

1. `#record_failure` wrote `generation_error` unconditionally while only
   transitioning a `generating` row, so any raise arriving after the row
   was terminal tagged a settled row. The first fix gated the write on
   `generating` — but that gate read the IN-MEMORY status, so on the
   inline-`perform_now` race it still relabelled a committed `completed`
   row. The gate is now a re-read of COMMITTED state under the write
   lock (`#settle_under_lock`), which is what actually closes this hole —
   see [[docs/explanation/bill-summary-failure-logging.md|bill-summary-failure-logging.md]]
   for why `BEGIN IMMEDIATE` makes the read-check-write atomic on SQLite.
2. `PasteSummaryService` is a THIRD writer of the summary body and never
   cleared the column, so a paste that supplied positions still rendered
   "were not generated" above the pasted cards. It now clears
   `generation_error`, as both generate paths already do.

The third hole was a VIEW concern: `BillCreatorLlmSummaryStatus` used to route a `skipped` row that kept an earlier summary into `LlmSummaryCompletedView` too, so this notice could render on a row the rule above says nothing about. That is fixed now: `LlmSummaryPositionsErrorNotice` returns null unless the row's status is `completed`.

### Writers of generation_error on a completed row

On a COMPLETED row, `generation_error` can come from this rescue, `#discard_withdrawn_positions!`, or an ungrounded summary draft recorded by `SummaryRunPersistGuard`.

These run after the summary this execution bought is committed, and all can leave the row `completed`. The positions persist clears `generation_error` only when the column was blank or on a resume retry, preserving any prior validation error attached to an ungrounded summary draft. This rescue itself writes `generation_error` without the locked re-check so the operator sees why positions are absent.

## draft_org_positions is deliberately NOT touched here

`draft_org_positions` is state operators edit.

`draft_org_positions` is state operators edit — `BillDraftOrgPositionsController` hard-deletes rejected drafts and merges operator edits into the survivors, one audit entry per decision — so clearing it on a passing failure (say, a 429 rate limit) would destroy triage work for a failure class this code calls transient and does not even retry. The rescue's own "the summary was already paid for" argument applies word for word to this column. Only a SUCCESSFUL positions call overwrites it.

## Dropping a dirty payload before it can re-raise

`update!` can assign a payload it then fails to save (`JSON::GeneratorError` is raised during save, AFTER assignment).

Without a fix, the value would stay dirty and `mark_completed!`'s save would re-raise it — past this rescue, into the catch-all — which is the exact failure this block exists to prevent. The rescue calls `provisioning.reload` rather than `restore_attributes`: dirty tracking for a `serialize`d column runs the coder to decide what changed, so an in-memory revert is not reliable for the exact payload that broke the coder. Everything worth keeping is already committed by this point, so a refetch loses nothing.

## Why prompt construction sits inside the begin/rescue

Building the positions prompt belongs INSIDE the guarded region, not above it.

`BillPositionsPromptBuilder` reads `extracted_testimony` — mutool output composed from publicly submitted PDFs — and runs regexps over it, so it can raise in its own right. When construction sat above the `begin` it bypassed this rescue entirely and reached the catch-all below, wrapping a testimony-parsing failure as a job-level `TransientBillSummaryError` instead of the graceful "positions absent, summary intact" outcome this rescue exists to produce.

## Why "(the summary is valid)" is conditional on the row's own state

The rescue's stored message adds "(the summary is valid)" only when one is actually on the row.

On a testimony-only bill the summary call was skipped for want of bill text, so an unconditional clause here would claim a body that does not exist. The row's own state answers the question — `provisioning.reload` just refetched committed state — and the no-summary settle at the end of `#perform` replaces this message anyway on the path where it lands (see [[docs/explanation/bill-summary-nothing-to-generate-settlement.md|bill-summary-nothing-to-generate-settlement.md]]).

## No testimony this run does not mean invalid positions

There is deliberately no `else` clearing `draft_org_positions` when the positions call is not attempted at all.

After positions were dropped from the summary output contract, that branch was the only writer for a testimony-less bill, and it always wrote `[]`. "No testimony on this run" is an ingest condition — unfetched attachments, a 404, mutool missing on the Pi — not evidence that persisted positions are wrong, and `paste_summary` explicitly supports supplying positions for a bill with no testimony at all. The "no testimony ⇒ no positions" contract is a VIEW rule, enforced off `has_testimony`; enforcing it here by deleting an audited operator record would be the same data loss the rescue above refuses to inflict on `draft_org_positions`.

### Why the spec's curated-positions fixture matters

`draft_org_positions` is state an operator edits, not a scratch pad the LLM freely overwrites.

`draft_org_positions` is state an operator edits, not a scratch pad the LLM freely overwrites: `BillDraftOrgPositionsController#update` deletes a rejected draft from the array outright and merges the operator's edits into the ones that remain, writing a `PipelineActivityLogger` audit entry for each change. A spec fixture standing in for this array should therefore look like an array a human has already worked through — not a fresh, unedited LLM response — because the whole point of the no-`else` rule above is protecting exactly that worked-through state from being silently wiped.
