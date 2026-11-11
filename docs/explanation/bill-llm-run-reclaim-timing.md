---
mode: explanation
summary: "Explains the worst-case timing bound behind RECLAIM_ABANDONED_AFTER and the design of the reclaim that frees a row a dead worker left stuck."
status: agent-extracted
related: [docs/explanation/abandoned-run-reclaim.md]
---
<!-- vale Vale.Spelling = NO -->

# Reclaiming a stuck bill-summary run: timing and design

`GenerateBillSummaryService::RECLAIM_ABANDONED_AFTER` (1 hour) is how long a
row may sit in a non-terminal status (`pending` or `generating`) with no
write before an operator's Generate click is allowed to reclaim it. See
[abandoned-run-reclaim.md](abandoned-run-reclaim.md) for the shared
`reclaimable?` judgement itself, who owns a reclaimable row, and why the
recovery can only be reached by an operator who does not need it. This
document covers what that one does not: the timing bound and the design of
`#reclaim_abandoned_run!`.

## Why one hour is safe

One hour is comfortably above the job's worst case.
`GenerateBillSummaryJob` puts a fully failing job at about 20 minutes of
wall clock (SDK retries, at most 2 per call, nested under three
`:polynomially_longer` job attempts at roughly 3s/18s/83s), and within a
single execution the longest quiet window is one adapter call — a 120s
timeout with 2 SDK retries — because every state transition and every
persist bumps `updated_at`. An hour therefore cannot cut a healthy run short.

## Both stuck states, not just one

`#reclaim_abandoned_run!` covers BOTH stuck states, not only `generating`.
A `pending` row whose job never runs at all (queue database lost, job
dropped) is stuck exactly as permanently, because the stale gate that would
rescue it lives inside the job that never runs. Fixing only one arm of a
two-arm guard is a recurring defect shape in this subsystem.

Each arm uses an edge the state machine already has — `generating ->
failed`, and `pending -> skipped` (the terminal state a row can be re-armed
from) — so no model change is needed. Those two edges live in
`SummaryRunRelease`, their only home; `#reclaim_abandoned_run!` only
decides whether to reach for them and logs it.

No `generation_error` is written, and no paste is handed off:
`GenerateBillSummaryService#call` re-arms the row microseconds later, so a
message here would only ever be read by the code that erases it, and the
operator's own click is the one route that deliberately replaces a pasted
body. Both follow from `rearmed_by_caller: true` in `SummaryRunRelease`.

## What this cannot reach on its own

Before this reclaim existed, the only escape for a `generating` row a dead
worker abandoned was a fresh full pipeline run over the whole bill —
re-paying for every other bill in it — because the job's own stale-run gate
only rescues `pending`, and only from inside a job that, in this scenario,
never runs.

## Finding the current readers

`BillLlmProvisioning#reclaimable?` is the single definition of the
judgement this reclaim acts on. Run `grep -rn "reclaimable?" app config lib`
for the current set of readers rather than trusting a list here — a written
census goes stale the moment a reader is added or removed, and a stale
census reads as complete.

The case this service itself creates is handled differently:
`#release_unqueued_row!` undoes the arm when the enqueue fails, so the row
never reaches a status its own controls refuse.

## STALE_AFTER and the pre-call stale-job gate

`GenerateBillSummaryJob::STALE_AFTER` (1 hour) is the sibling cutoff to
`RECLAIM_ABANDONED_AFTER`, for a different problem: skipping a summary job
that has sat in the queue this long since it was last (re-)enqueued. When
the worker drains a backlog that piled up during an outage, an old job has
probably been superseded by a newer one, so summarizing it again only
burns API budget. The cutoff sits well above the roughly-20-minute retry
window (see "Why one hour is safe" above), so it never cuts off a healthy
retry chain partway through.

The gate runs AFTER loading the row but BEFORE
`enqueue!`/`start_generating!`/`Llm::Client.build`, so a skipped job still
spends zero API budget. A bare `return` there would not be enough: the
service flips the row to `pending` before enqueuing, so returning would
strand it at `pending`, and the service's `:already_in_progress` guard
would then block every re-trigger. `#mark_stale_skipped!`
moves a pending row to `skipped` (a terminal state) so the next trigger can
start it fresh, under a row lock so a concurrent inline `perform_now` (the
pipeline) that already advanced the row is not clobbered back. It never
clears `llm_summary`/`full_breakdown`/`draft_org_positions`, so a summary
that completed earlier survives. Inline `perform_now` (seeding and the
pipeline) has `enqueued_at == nil` and is never skipped by this gate.

## mark_stale_skipped!: resolving a stranded pending row

`#mark_stale_skipped!` resolves a stranded `pending` row left behind by the
service when its job is skipped as stale. The lock reloads
under a pessimistic row lock (`BEGIN IMMEDIATE` on SQLite WAL — the same
write barrier `PipelineRunStage` uses), so the `pending?` re-check and the
`mark_skipped!` write are atomic: a concurrent inline `perform_now`
(`RunLegislationPipelineJob`) that drove the row to generating/completed in
the gap since `#perform` loaded it is NOT clobbered back to `skipped`. A
nil row, or a row a newer job already settled, is left untouched.

It uses `#settle_under_lock`, not a bare `with_lock` — it was the only
lock site in this class that was not. A row destroyed in the window since
`#perform`'s load raises `RecordNotFound` out of `lock!`, into the
method-level catch-all, which wraps it `TransientBillSummaryError` and
re-raises — so `retry_on` restarts the very job this gate decided must not
run. Attempt 2 carries a fresh `enqueued_at`, so the stale test no longer
trips, the missing row is rebuilt, the arm takes `:arm_free_row`, and the
skip that was meant to spend nothing pays for both calls.

The spec pinning this stubs `lock!` to raise `RecordNotFound`, rather than
destroying the row from the test: destroying the row from a spec cannot be
timed into the microseconds between `#perform`'s load and this gate's own
`lock!` call, so the raise itself — not a real deletion race — is what the
stub puts under test.
