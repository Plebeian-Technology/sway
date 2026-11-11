---
mode: explanation
summary: "Explains why clearing supplemental testimony needed its own endpoint instead of reusing generate_summary or regenerate_summary."
status: agent-extracted
related: [docs/explanation/supplemental-testimony-write-rule.md]
---

<!-- vale Vale.Spelling = NO -->

# Why supplemental_testimony has its own endpoint

`PATCH /bills/:id/supplemental_testimony` saves or clears an operator's
supplemental testimony without running the summary model. See
[the supplemental-testimony write rule](supplemental-testimony-write-rule.md)
for how the write itself decides between clear, blank, and present.

Clearing requires an explicit `clear_supplemental_testimony` flag, and
nothing in the UI sent one until this endpoint existed, so clearing could
only be done through the API before. Neither `generate_summary` nor
`regenerate_summary` could host a Clear button instead: both spend a model
call, so an operator deleting text they pasted by mistake would pay for a
regeneration they never asked for — and on a bill with no source text,
generation is refused outright, which would take the clear down with it.
A dedicated endpoint that writes nothing but the testimony column sidesteps
both problems.

## Test fixture note

`storedSupplemental` is the value the SERVER has saved, and it decides
whether the Clear button shows. `""` here means nothing is stored, so no
Clear button appears.

## Why the frontend threads onClearSupplemental separately from supplementalText

`BillCreatorLlmSummaryStatus` passes `onClearSupplemental` separately from
`supplementalText` because the Clear button must react to what the
database holds, not what the operator has typed.

## UpdateSupplementalTestimonyService implementation notes

`UpdateSupplementalTestimonyService` writes one column and queues no work.
It is NOT a general-purpose way to edit the bill's provisioning row: the
only field it can write is the one the operator typed into.

Its `initialize` applies the same guard `GenerateBillSummaryService` uses
on the incoming value: `supplemental_testimony` arrives straight off the
request, so a client sending `supplemental_testimony[]=x` or
`supplemental_testimony[a]=b` would hand an `Array` or a `Hash` to a text
column. Anything that is not a `String` counts as nothing sent.

`#call` fetches (or builds) the bill's `bill_llm_provisioning` row BEFORE
deciding what to write, because a paste that REPLACES stored testimony also
withdraws the draft positions that were based on the old text, and working
that out needs the old value. Building the object here saves nothing to the
database — if the request ends up doing nothing, the bill still has no
provisioning row. A brand-new record has no saved row to lock and no drafts
to withdraw, so it skips straight to the write.

For an existing row, withdrawing those drafts means reading
`draft_org_positions`, changing it, and writing it back — and an operator
hitting Reject or Edit at the same moment rewrites the same field.
`with_lock` re-reads the row inside a transaction, and
`config/database.yml` sets `default_transaction_mode: IMMEDIATE`, so no
other connection can slip a change in between the read and the write.

`#write` treats clearing a column on a row that does not exist as a no-op,
because it changes nothing — so it must not WRITE anything either. A clear
always produces `{supplemental_testimony: nil}`, which is not an empty
attrs hash, so an earlier version of this check let `update!` through and
INSERTED a row whose every column was nil. That row was not harmless: the
Bill Creator decides which summary screen to draw by asking whether a
provisioning row exists at all, so one press of Clear on a bill that had
never been summarized swapped the "no pipeline data" screen — the one
carrying the Prepare prompt and Paste summary JSON — for the status screen,
showing nothing. The fix checks the written VALUE, not the flag: a first
paste on a new row legitimately creates it, and that path arrives with a
string, so it is not caught by the same no-op check.
