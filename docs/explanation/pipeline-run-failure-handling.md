---
mode: explanation
summary: "Explains four design decisions inside handle_run_failure, covering state transitions, activity logging, error rescue scope, and preserving the original error."
status: agent-extracted
related: []
---

<!-- vale Vale.Spelling = NO -->

# How RunLegislationPipelineJob#handle_run_failure is built

`#handle_run_failure` is the single place a run gets marked failed. This
document explains four decisions inside it, in the order they run.

## Choosing mark_failed vs force_fail

`force_fail` is declared with `PHASE_52_NON_TERMINAL_STATES => :failed`, a
superset of the queued/running states `mark_failed` covers. An earlier
"prefer force_fail" version always took the `force_fail` branch, which made
`mark_failed` dead code and mis-tagged routine queued/running failures as
operator-initiated `force_fail` events in the audit log — and audit-log
consumers tell events apart by which event fired.

`handle_run_failure` therefore prefers the more-specific `mark_failed` when
available (queued/running), and keeps `force_fail` for the mid-stage
`*ing_*` cases it was designed for. When neither guard fires, it logs
explicitly so an operator reading the log can tell "intentional no-op"
from "state machine missed."

## Activity log ordering

`log_stage_failed!` writes an error-severity row to the Activity Log.
Without it, a failed stage left only an info-severity `state_transition`
row (see `emit_state_transition!`). The Activity Log stayed silent about
the one failure that matters most.

This call runs after the run's terminal state transition above, not
before. An earlier version ran it first: if the write raised, the rescue
clauses below caught it before the run ever reached `"failed"`. A busy
database can raise that way, and the run then stayed stuck as `"running"`
forever.

`current_stage` still names the stage that failed at this point. No
terminal transition clears it, and `STAGE_STATUS_TO_DAG_NAME` has no
`"failed"` entry.

## Swallowing only ActiveRecord errors

A previous `rescue StandardError` silently swallowed every exception
raised inside this handler — including a
`StateMachines::InvalidTransition` fired when `force_fail!` /
`mark_failed!` hits a state the machine cannot leave (for example, a
fresh-origin `perform` on a run whose status was manually advanced past
`:queued`). That swallow left the run stuck in its original status with no
audit-log row for the failed transition, and the operator paged by the
`SwayLogging.error` call above had no clue what stopped the recovery.

ActiveRecord-internal errors (`RecordInvalid`, `RecordNotFound` on the
audit-log subject reload, `Deadlocked` / `StaleObjectError` under
contention) are the only kind that legitimately should not escape a
failure handler — the outer `perform` rescue can do nothing useful with
them. Everything else (`StateMachines::InvalidTransition`, the job's own
`StageError`, `NoMethodError`, and so on) is valuable evidence; it
re-raises so the `perform`-level rescue routes it and the operator sees a
structured failure instead of a silently stuck run.

## Preserving the original error through a secondary failure

A non-ActiveRecord error raised inside `handle_run_failure` (say, a
state-machine `after_transition` callback raising `NoMethodError` or
`KeyError` because `SEVERITY_FOR_EVENT` and `TITLE_TEMPLATES` drifted
apart) would otherwise escape and replace the original `error` at the
`perform`-level `rescue ... raise` — when an exception leaves a rescue
body, Ruby substitutes it for the one being re-raised. The operator would
then see the secondary `KeyError` instead of the `StageError` /
`BillProcessingError` that actually caused the failure.

`handle_run_failure` logs the secondary failure together with the original
error's context, then swallows it so the caller's `raise` re-raises the
original `error` faithfully. Solid Queue lock release is unchanged — the
job still ends loudly with the original failure class on the
`SwayLogging.error` path.

## Why OperatorAbortError bypasses handle_run_failure entirely

`OperatorAbortError` is raised by the pipeline orchestrator when it
notices that someone else has already moved the `LegislationPipelineRun`
row to a terminal status (failed / cancelled) — typically because the
operator hit the Force-Fail button on the BillCreator page, which POSTs
to `/pipeline_runs/:id/force_fail` and flips the run via the state
machine's `force_fail` event.

It is distinct from `StageError` (a run-level fatal error the
orchestrator itself escalates) and `BillProcessingError` (a single bill
failing). The orchestrator rescues `OperatorAbortError` separately so it
does NOT call `handle_run_failure` — the run is already in a terminal
state, so trying to `mark_failed!` it would raise
`StateMachines::InvalidTransition` and clutter the audit log with a
redundant "force-fail → failed" entry.

`OperatorAbortError` carries the stage name and processed-bill count so
the structured log line at the rescue site can answer "where did the
operator's abort land?" without an extra DB query.

## Why spec/system/admin_pipeline_run_controls_spec.rb exists

Browser tests for the two admin buttons that kill pipeline runs — Force
fail (type a phrase into a dialog to stop a run that is in flight) and
Sweep stale (mark every non-terminal run as failed, keeping the rows so
admins can still audit them) — were until now covered only by request
specs and frontend unit tests. The page setup copies the admin
pipeline-tab spec for bulk-deleting orphans; signing in uses the test-only
session route (`sign_in_as_admin`) plus a swapped admin-phone list, so no
passkey ceremony is needed.

## Why the sweep example watches the database, not the page

Sweep posts without a bill id, so the server sends the browser to the
new-bill pipeline tab. That means the sweep button vanishing from the
originating page proves nothing about whether the sweep worked. What the
server did to the rows is the real signal, so the spec watches the
database until both runs land on `failed` rather than asserting on page
state after the redirect.
