---
mode: explanation
summary: "Explains the three values BillLlmProvisioning#summary_run_id can hold, why the run claim is a different shape from the purchase receipt, and why this column carries three meanings instead of a new one."
status: agent-extracted
related: [bill-summary-arm-row-ownership, arm-decision-table, paste-summary-status-reuse-and-pending-bug, bill-summary-supersede-gate]
---

# What `SummaryRunMarker` encodes, and why

`BillLlmProvisioning#summary_run_id` answers ONE question: which writer
owns this row. Its first meaning was `GenerateBillSummaryJob`'s `job_id`,
stored to say "this enqueue has spent money". `SummaryRunMarker` adds the
two other things that can own it.

## The three values, and the questions each answers

- **A bare `job_id`** -- THE PURCHASE RECEIPT. A previous execution of this
  enqueue already paid for and persisted a body. Written in the same
  statement as the body itself, so the two cannot disagree. Read by
  `GenerateBillSummaryJob#resumed_after_purchase?`.
- **`"run:<job_id>"`** -- THE RUN CLAIM. One execution has armed the row and
  is about to make its paid calls over it. Written by the arm and replaced
  by the receipt when a purchase lands, so the claim is what stands for the
  whole paid region and nothing else has to infer ownership from a status.
  Read by `SummaryRunArmDecision`, the table that decides what the arm may
  do with a row -- see
  [bill-summary-arm-row-ownership.md](bill-summary-arm-row-ownership.md)
  and [../reference/arm-decision-table.md](../reference/arm-decision-table.md).
- **`"operator_paste:<uuid>"`** -- a human wrote the body by hand.

## Why the claim is a different shape from the receipt

The two answer different questions, and the job asks both, one after the
other: the arm asks "is this row mine to work on", and the re-entry gate
asks "have I already bought what I came for". Writing the receipt's value
at the arm would make the second question answer yes for an execution that
had bought nothing, which skips the summary call for a summary that was
never made.

## Why this column, and not a new one

It already has the three properties needed for marking "something newer
replaced this", and it needs no migration:

- `GenerateBillSummaryService` CLEARS it inside the lock that sets the row
  up for a fresh generation. So "the operator deliberately asked for a new
  summary" already wipes the marker, which is exactly the rule wanted: a
  regenerate overrides a paste, while a pipeline run that happens to pass
  by does not.
- SEVERAL pieces of code read it, and they ask different questions of it,
  so any new kind of value has to be unambiguous to all of them.
  `SummaryRunArmDecision` is the one that asks all three shapes in one
  place, so it is the reader a new value has to satisfy first; the others
  ask "did THIS enqueue already spend money?" or "does a human own the
  body on this row?".

  No count of readers is given here on purpose. An earlier version of this
  note first said exactly one reader existed -- which was the argument for
  overloading the column -- and stopped being true the moment the second
  arrived. It was then corrected to three, in the same sentence that
  narrates having been wrong, and went stale again the moment
  `SummaryRunArmDecision` was extracted. A restated count is a fact with
  nothing behind it. Run `grep -rn "SummaryRunMarker\." app lib` for the
  current list; every reader goes through this class, so that grep cannot
  miss one.

  Nothing anywhere looks a row UP by `summary_run_id`; the late-arriving
  callback the column was built for no longer exists (it went away with
  the old Python summary service).
- The database index on it requires every non-null value to be unique,
  which is why `.operator_paste` returns a brand-new value each time
  instead of one shared fixed string. A constant would clash the moment
  two bills had summaries pasted into them.

## Why not `llm_provider == "operator_paste"`

`llm_provider` already says a human wrote the body -- nothing clears it
when the row is set up for a new generation, so it cannot say "replaced
SINCE this job was queued" -- it would lock a pasted bill out of
regeneration forever. Clearing it at setup time was the alternative, and
it is worse: `llm_provider` and `llm_model` are a matched pair recording
where the body currently on the row came from, and emptying them while
that body is still on screen swaps a true statement for a blank.

## Why not compare timestamps (`llm_generated_at` against `enqueued_at`)

This same bug turned up when the job-id meaning was added. `enqueued_at`
is rewritten on every retry, so on the second attempt it is NEWER than a
paste made between attempts, and the comparison says "nothing replaced it"
at exactly the moment it must say something did.

## `.run_claim`: why it is derived from `job_id` rather than random

The claim is what one execution stamps when it arms a row, so every other
execution can tell "another run is working on this" from "this row is
free". It is derived from `job_id` rather than random, because the
execution that has to recognise its OWN claim after a worker restart has
only its `job_id` to recognise it by.

It cannot collide with the receipt (a bare UUID never starts with `"run:"`)
or with a paste marker, so the three values stay tellable apart by shape.

## `.purchase_receipt?`: why the third shape gets a name here

More than one reader asks this question -- `GenerateBillSummaryJob`'s
re-entry gate and `SummaryRunArmDecision` -- and two hand-copied versions
of one rule is how the citation verdict and the paste marker each drifted
before.

`present?` matters in the check. A nil marker on a row whose `job_id`
happened to be nil would otherwise read as a receipt for a purchase nobody
made.
