---
mode: explanation
summary: "Explains design decisions in LegislationPipelineRun's status state machine: the initial state, stage-state ordering, terminal-status history, and why mark_cancelled reaches every per-stage state."
status: agent-extracted
related: []
---
<!-- vale Vale.Spelling = NO -->

# LegislationPipelineRun's status state machine

## Why the initial state is :queued, not nil

Unlike `BillLlmProvisioning.generation_status`, the state machine's initial
state is `:queued` (not `nil`), because every row in this table is a run
that was actually submitted.

## Why fetching_law is listed before extracting_text

`PHASE_52_STAGE_STATES` lists `fetching_law` before `extracting_text` to
match the order stages actually run in, which keeps the list greppable
against the stage graph. The order in this particular list is cosmetic —
the state machine's event declarations already declare every transition
either order would need — but matching run order makes the list easier to
scan against the pipeline stages it mirrors.

## Why mark_completed stays

The terminal-status events include `mark_completed`, kept for older rows
that already use `:completed`. New runs end in `:succeeded` (the canonical
success status) or `:partial` (at least one bill failed and at least one
succeeded).

## Why the per-stage X-ing states never appear in TERMINAL_SUCCESS_STATUSES

After `start_X!` the run sits in an `X-ing` state while that stage runs;
`complete_X!` returns it to `running`. These never appear in
`TERMINAL_SUCCESS_STATUSES` — only `succeeded` / `partial` / `completed`
count as a successful finish.

## Why mark_cancelled reaches every per-stage state

A worker that dies mid-stage (say, the host sleeps overnight) leaves the
run stuck in a per-stage `*ing_*` state. Operator cancel must reach those
too — `mark_cancelled` covers the same statuses as `force_fail` so a stuck
run can be cancelled, not only failed. Without this, cancel raises "Cannot
cancel run in status=..." for every per-stage state.

## Why TERMINAL_STATUSES is computed by subtraction

`TERMINAL_STATUSES` is every status a run can end in, worked out by
subtraction rather than written out by hand: `state_machine(:status).states
- PHASE_52_NON_TERMINAL_STATES`. A hand-written list and the non-terminal
list are two separate lists, so a status added to neither would be
silently treated as "not finished," and its run would never get a finish
time. Subtracting leaves no gap — a new status is terminal unless somebody
says otherwise. It is declared after the state machine because that is
where the full set of statuses first exists.

## Why TERMINAL_SUCCESS_STATUSES lists both completed and succeeded

Every code path that asks "did this run finish successfully?" must compare
against `TERMINAL_SUCCESS_STATUSES`, not a hardcoded `"completed"`.
`"succeeded"` is the canonical terminal status (inherited from the old
Python service's enum); legacy paths still write `"completed"`. Both mean
success — checking only one silently rejects valid runs, which is exactly
how the seed task once treated healthy pipelines as failures.
