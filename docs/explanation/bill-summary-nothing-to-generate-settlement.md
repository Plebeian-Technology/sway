---
mode: explanation
summary: "Explains the two cases where a bill-summary run buys nothing and must settle the row as failed instead of falsely marking it complete."
status: agent-extracted
related: []
---
# Settling a run that bought nothing

<!-- vale Vale.Spelling = NO -->

`GenerateBillSummaryJob#perform` has two arms that handle a run where the
summary call was skipped (`parsed` is `nil`). This document covers both:
the arm for a bill with no source text and no testimony, and the arm for
a bill with testimony but no bill text.

## Arm 1: both spend gates closed

When both the summary call and the positions call were skipped, zero
adapter calls were made, nothing was written to the row, and there is
therefore no summary to claim.

`#settle_completed` used to run unconditionally in this situation, which
meant a bill with no source text and no testimony landed `completed` with
`llm_summary` nil and `llm_generated_at` nil. That is not a cosmetic
mislabel — it is a green "Ready" badge that CANNOT be contradicted:
`BillCreatorLlmSummaryStatus` routes `completed` to
`LlmSummaryCompletedView`, which renders the Ready badge over
`llm_summary || ""`; `BillLlmProvisioning#stale?` compares against
`llm_generated_at` and so is permanently false while it is nil, meaning no
stale chip ever appears; and the operator's only available action,
Regenerate, routes back through `GenerateBillSummaryService` and returns
`:no_pipeline_data`. The operator was shown a bill that is Ready and has
nothing, with no way to learn otherwise.

This was previously masked for nearly every bill: `diff_content` kept
`source_present?` true, so the summary call fired (and was billed)
instead of reaching this arm. Narrowing that gate made this the DEFAULT
outcome for a non-amending Legistar matter with no PDF, which is why the
two changes (narrowing the gate and adding this settlement arm) land
together — the gate fix alone would have traded a billing bug for a
silent empty-summary bug.

### Why `failed`, not a new `generating -> skipped` edge

The operator needs the reason, and `failed` is the only terminal status
whose render paths show it, BOTH of them:
`BillCreatorLlmSummaryStatus` sends a bare `failed` row to
`LlmSummaryGenerateBranch`, which displays `generation_error`; a `failed`
row that still holds drafts or an earlier summary goes to the completed
view instead, where `LlmSummaryFailedReasonNotice` displays it. That
second path matters here: this settle never clears `draft_org_positions`,
so an ordinary regenerate leaves them on the row and takes it.

`skipped` shows the reason on neither path: the generate branch carries
no explanatory copy for it, and on the completed view
`LlmSummaryFailedReasonNotice` deliberately stays silent for `skipped`,
because a skipped row's stored error belongs to the prior run whose
summary is on screen.

The completed-row rule (see
[bill-summary-paste-hand-off-rule.md](bill-summary-paste-hand-off-rule.md))
is untouched: it constrains `generation_error` on a COMPLETED row, and
this row is not completed. `failed -> pending` already exists, so the
operator can re-run after extract-text or fetch-hearings produces
something, or after pasting supplemental testimony.

This arm returns `SETTLED` (see
[bill-summary-perform-return-contract.md](bill-summary-perform-return-contract.md)),
and that is right rather than a leftover gap: the stage ran, correctly
determined there was nothing to buy, and settled the row. The
operator-visible signal is this row's `failed` status and its stored
message, not a claim that a summary exists. Paths that produce nothing
AND settle nothing return `NOT_RUN` instead, and the pipeline records
those as "not_run" so `resume` comes back for them.

### When this arm does NOT fire

Only when there is no summary to show. A run that bought no new summary
over a row that already holds one leaves a row that is genuinely
complete, and flipping it to `failed` would write "nothing to summarize"
above a summary that exists.

This arm can only reach an empty row if one of three things outside this
file stops holding: `MupdfExtractor` raises rather than returning empty
text, `bill.extracted_text` has exactly one writer, and a pasted summary
carries a marker the supersede gate at the top of `#perform` stands down
on (see
[bill-summary-supersede-gate.md](bill-summary-supersede-gate.md)). Those
three are what make a summary without source text unreachable — none of
them is enforced here, and `RunLegislationPipelineJob`'s inline
`perform_now` reaches this line without passing
`GenerateBillSummaryService#runnable?` at all. The check costs one
condition; depending on the three costs a completed row.

## Arm 2: testimony present, but no bill text

The guard above closes the case where both inputs are missing. A bill
with testimony but no bill text takes the positions call and skips the
summary call, so `parsed` is `nil` here too — and this used to fall
straight through to `#settle_completed`, producing every consequence
described above: a green Ready badge over an empty summary, with
`llm_generated_at` nil so `#stale?` can never contradict it, and
Regenerate landing back in the same place because
`GenerateBillSummaryService#runnable?` is satisfied by the testimony.

Splitting the positions call out CREATED this state. Before that, the service refused a
testimony-only bill outright; opening that path is what makes "testimony
but no bill text" an ordinary outcome rather than an impossible one.

### When this arm does NOT fire

Only when there is no summary to show. A REGENERATION that bought no new
summary still has the previous one on the row, and that row is genuinely
complete — its summary is simply older, which is what `llm_generated_at`
already records and `#stale?` already reports.

### Why `failed`

For the same reason arm 1 uses it: it is the only terminal status whose
render paths show `generation_error`, and the operator needs the reason.
The drafts bought by the positions call stay visible —
`BillCreatorLlmSummaryStatus` routes a terminal row that still holds a
summary or drafts to the completed view, which draws the true badge and
`LlmSummaryFailedReasonNotice` above the summary editor.
(`LlmSummaryPositionsErrorNotice`, further down that view, is the
`completed` case only: an error there means the positions call failed.)

`positions_failed_reason` is passed because the stored message is the
whole operator-visible output of this path, and "the positions below are
unaffected" is only true when the positions call actually landed. On a
testimony-only bill, that call is the ONLY paid call of the run, so when
it fails, this settle is where the operator learns why — it overwrites
the note the positions rescue itself wrote (see
[bill-summary-positions-error-handling.md](bill-summary-positions-error-handling.md)).

## Why each stored message says what it says

`NOTHING_TO_GENERATE_ERROR` names both missing inputs and how to fix each
one, because the row it lands on shows this string and nothing else about
why the run produced nothing.

`NO_SOURCE_TEXT_ERROR` covers the sibling case: testimony WAS there, so the
positions call ran and its drafts are on the row, but there was no bill
text, so no summary was bought. It states both halves — the positions
below are real, the summary is absent — because the row otherwise looks
like a finished summary of nothing.

`NO_SOURCE_TEXT_POSITIONS_FAILED_ERROR` is the same run when the positions
call FAILED. On a testimony-only bill that call is the only paid call of
the run, so its failure leaves the row with nothing on it — and
`NO_SOURCE_TEXT_ERROR`, which points at positions "below," then states two
things that are not true. This message names the real failure, which
otherwise lives only in the log, and tells the operator what Retry will
do: the summary call stays skipped for want of bill text either way, so
the retry is a second try at the positions call and nothing else.
`%{reason}` is the scrubbed adapter message; see
[bill-summary-error-message-budget.md](bill-summary-error-message-budget.md)
for how it is fit into the template.

`NO_SOURCE_TEXT_NO_POSITIONS_ERROR` is the third state of the same settle:
the positions call worked and named no organization, so the row holds no
positions and none render below the message. Pointing the operator at
positions that are not on screen sends them looking for something that is
not there.
