---
mode: explanation
summary: "Explains the rule LlmSummaryPositionsErrorNotice relies on, the two display-side bugs that made it untrue, and the wording bug it does not repeat."
status: agent-extracted
related: [docs/explanation/bill-summary-positions-error-handling.md, docs/explanation/bill-summary-published-vs-draft-box-bug.md]
---
<!-- vale Vale.Spelling = NO -->

# Why LlmSummaryPositionsErrorNotice reads the way it does

`LlmSummaryPositionsErrorNotice` only draws on a `completed` row that also
carries a `generation_error`. That combination has exactly one cause: the
rescue inside `GenerateBillSummaryJob` that catches a failure in the
positions call, after the summary itself already landed (see
[bill-summary-positions-error-handling.md](bill-summary-positions-error-handling.md)
for why that rescue exists and what it can and cannot mean). So a
`completed` row's `generation_error` means "the summary is good, but the
positions call did not land" — a message the operator was meant to see and,
for a while, had nowhere to see.

## Two things used to make this notice untrue

**(a) `skipped` rows.** `BillCreatorLlmSummaryStatus` routes a `skipped` row
that kept an earlier summary into `LlmSummaryCompletedView` too, so this
notice could appear on a row the rule above says nothing about. Checking
`generationStatus !== "completed"` here is the display-side half of that
fix; the server-side halves live in the linked doc.

**(b) A list with drafts in it.** A positions failure deliberately KEEPS the
existing `draft_org_positions`, because they may be work an operator sorted
through on an earlier run. So "were not generated" used to print directly
above cards that exist and are perfectly valid — the wording assumed an
empty list. The `hasDrafts` prop switches the title to "were not
refreshed" instead. Each underlying behavior (keep the drafts, keep the
error) was already right; only the notice's wording lagged behind it.

A `failed` row reaches the completed view through the same
terminal-with-content route, and its error is a different class of thing —
no source text, nothing to generate. `LlmSummaryFailedReasonNotice`, above
the editor, words that case; this notice stays about the positions call
specifically and returns null for `failed`.

The notice blocks nothing — warning styling, never the destructive red used
for errors. The summary itself is fine and every action on it stays
available.

## The "summary above" wording bug

The notice used to say "the summary above is unaffected," and for a while
that sentence pointed at the wrong box. A fix moved the editable summary
box from `bill_llm_provisioning.llm_summary` (the model's draft) to
`bills.summary` (the published text, which no run writes) — see
[bill-summary-published-vs-draft-box-bug.md](bill-summary-published-vs-draft-box-bug.md).
Two later fixes swept the other notices that still described the old
column; this one predates both fixes and was missed. "Above" was
positionally right and about the wrong thing: this sentence's job is to say
the paid summary call succeeded, and it pointed at a box the run neither
wrote nor could have harmed. On a bill ingested by
`LegislationIngestionService` that box literally reads "Summary pending,"
so an operator reading the old wording could conclude the run produced
that text and it was fine — with the model's actual summary one toggle
away in `LlmSummaryDraftNotice` and no reason to go look for it. The
notice now names the published summary the way its two swept siblings
name it.

## Why the notice says "before this run", not "from an earlier run"

"from an earlier RUN" is one word further than the row can prove, and here
it is unprovable rather than merely unproven. The cards can be an
operator's own paste: `PasteSummaryService` writes `draft_org_positions`
and clears `generation_error`, and a later Regenerate persists the summary
— writing `llm_provider` over `"operator_paste"` in the same statement —
before the positions call raises and the rescue keeps the drafts. So by
the time this notice draws, NO column on the row separates a pasted
position from a generated one, and `LlmSummaryDraftNotice`'s
`llm_provider` branch is no help. An operator who hand-entered five
positions from a hearing reads that they are stale output and re-enters
the work. "before this run" is what the kept drafts do prove.
