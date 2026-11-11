---
mode: explanation
summary: "Explains the pipeline's per-bill stage status values beyond succeeded/failed, including skipped and not_run, and how each is counted and reported."
status: agent-extracted
related: []
---

<!-- vale Vale.Spelling = NO -->

# Pipeline bill stage status model

`pipeline_run_bills.stage_results` records one outcome per bill-level stage,
per bill. This document explains why the model has more than "succeeded" and
"failed," and what each of the other statuses means.

## skipped: a bill with no PDF attached

When `execute_extract_text` returns `:skipped_no_pdf` (a Legistar matter
with no PDF attached), `RunLegislationPipelineJob` records the bill as
`"skipped"` — not `"failed"`. Skipped does not bump `consecutive_failures`
(so a Legistar response with 5 or more no-PDF bills in a row no longer trips
the failure budget) and counts as success for `#stage_already_succeeded?` on
resume. The bill stays visible in the per-bill grid with a clear skip
reason, so an operator can attach a PDF by hand and re-run if needed.

## not_run: nothing was produced, but nothing failed

`GenerateBillSummaryJob::NOT_RUN` is not `"succeeded"` and not `"skipped"`.
Both of those count as done for `#stage_already_succeeded?`, and a bill
whose stage returned `NOT_RUN` is not done — nothing was produced for it.
`"not_run"` is the one status resume comes back for.

It is not `"failed"` either: nothing went wrong. Another writer owned the
bill's summary row, or the row was deleted mid-flight. Recording a failure
would bump the consecutive-failure budget and could abort a run over an
ordinary overlap.

The `"not_run"` status is recorded with no cause named, because `NOT_RUN`
carries four possible causes and the caller cannot tell them apart: a live
run holds the row, the row moved between load and lock, an operator's paste
already settled it, or the row was deleted. Only the first of those is
"another writer owns the row" — the paste case has a human owner and a
finished summary, and the deleted case has no owner at all.

Of the four, "a live run holds the row" is the most reachable in practice:
an operator's queued job can sit inside its own paid region for up to six
minutes, and any pipeline run that reaches the same bill during that
window hits this path — a much wider and more ordinary overlap than a
row deleted mid-flight or the load-to-lock race the staleness swap closes.

## Why "the row was deleted" matters most among the four

Of the four `NOT_RUN` causes, "the row was deleted" is the one that
matters most for resume to actually pin, even though it is not the most
FREQUENT: for the other three causes some other writer (the live run, the
operator's paste) will eventually settle the row, so a resume that came
back anyway would find nothing left to do. The row-gone case is the one
where NO other writer exists to settle it — the bill genuinely needs the
pipeline to come back and try again, or it never gets a summary.

`GenerateBillSummaryJob` has two separate row-gone gates that both have to
answer `NOT_RUN`, not one: the arm's half (`#arm_row_unless_owned!`
returns `nil` when the row vanished while the arm held it) and the
pre-call clear's half (`#clear_stale_run_state_unless_superseded!`
reached by a positions-only resume, which never goes through the arm at
all — a row destroyed inside the arm never reaches this second gate,
since the arm answers first). Each is pinned by its own spec because
either one alone being wrong would silently strand a bill.

Both specs stub at the gate boundary rather than destroying the row from
the example: the actual window — the microseconds between one lock
committing and the next one taking its own — cannot be timed into from a
spec. The gate under test still runs for real; only the row's
disappearance is simulated.

The value is persisted so a reader of `pipeline_run_bills` can tell
`"not_run"` from `"succeeded"`, and that is its whole reach. No screen
renders it: `ResourceCachePanelSerializer` returns nil for every status but
`"succeeded"`, and `RunSummarySerializer` publishes no per-stage data (see
[Reporting bills nothing ran for](#reporting-bills-nothing-ran-for) below,
which makes the same point). A named cause here would be a specific wrong
answer sitting in the database with nothing to correct it — the job's own
log line names the real one.

## The summarize dispatch path

`RunLegislationPipelineJob#execute_bill_level_service`'s `:summarize` arm
goes through `#resolve_bill!` like its `else` arm does. The old
`perform_now(bill.id) if bill` silently did nothing when the bill was nil,
recorded the stage `"succeeded"` with no summary produced, and left resume
skipping the bill forever.

The same kind of harm survived one branch over, in `GenerateBillSummaryJob`
itself, and the job's return value is what closes it.
`GenerateBillSummaryJob` has several paths that return normally having
produced nothing: the declining rows of its arm decision, and the two "the
row is gone" returns. The most reachable is an operator's queued job still
inside its paid region — up to six minutes — when this run reaches the same
bill. That is a routine overlap, and the job's own arm calls it "the
ordinary case, not an edge one."

`:not_run` is carried out of `GenerateBillSummaryJob` and turned into a
`"not_run"` stage result by the caller, which `#stage_already_succeeded?`
does not accept — so resume comes back for the bill instead of skipping it
forever.

## Counting stage success

`RunLegislationPipelineJob#run_bill_level_stage` counts how many bills got
through a stage using SQLite's `json_extract` to read the `stage_results`
JSON. Skipped bills count as success here — the question this guard asks is
"did anything go right in this stage," and a clean skip (a no-PDF Legistar
matter) is not a failure. The all-skipped case (Legistar returned zero
bills with PDFs) is still visible: the count equals
`pipeline_run_bills.count`, but every per-bill row says
`status="skipped"`/`error="no_pdf_uploaded"`, so an operator asking "why
did no extractions run" gets a loud answer.

`"not_run"` counts here too, and only here. Nothing went wrong for those
bills — another writer owned the row — so aborting the whole run as "all
bills failed" would be a worse answer than carrying on. It deliberately
does not count for `#stage_already_succeeded?`, which is the reader that
decides whether resume comes back for the bill.

## Reporting bills nothing ran for

A bill whose stage recorded `"not_run"` is deliberately not a failure:
nothing went wrong, and counting it would abort whole runs over an ordinary
overlap between an operator's click and a pipeline run. That stays.

What it rests on is "resume comes back for them" — and resume is an
operator action that nothing prompts. `"not_run"` reaches no screen either:
`stage_results` goes to the frontend through
`ResourceCachePanelSerializer`, which returns nil for every status but
`"succeeded"`, so the panel shows an absent artifact and no reason for it.
A run in which every bill's summarize was declined therefore reported a
plain green and said nothing.

`RunLegislationPipelineJob#report_bills_nothing_ran_for` is the durable
record of that. It does not change the run's status — only what an
operator can find out about a green one.

## Why SETTLED must still count as done, checked through the resume gate itself

The counter-example to `NOT_RUN`: `GenerateBillSummaryJob::SETTLED` must
keep counting as done, or resume comes back forever for a bill another
writer already finished settling.

The regression this guards against lived beside
`#execute_bill_level_service` and asserted only that a stub returned what
it was told to return — it recorded nothing and read nothing back, so
moving `SETTLED` into the `not_run` branch (the exact over-correction that
would break this) left that assertion green. The fix is a spec that reads
what `RunLegislationPipelineJob` actually wrote to `stage_results` and
feeds it back through `#stage_already_succeeded?`, the same resume gate
production code uses, instead of asserting against the stub's return value
directly.
