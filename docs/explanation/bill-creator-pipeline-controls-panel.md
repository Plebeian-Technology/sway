---
mode: explanation
summary: "Why BillCreatorPipelineControls threads subscriptionState down for its own paused banner, computes runDisabledReason as a named string instead of a title= wrapper, and how its various inline notices (cable-downgrade, pinned-run conflict, force-fail dialog) are gated."
status: agent-extracted
related: [docs/explanation/pipeline-controls-pending-state-race.md, docs/explanation/pipeline-terminal-alert-remedy-wording.md]
---
<!-- vale Vale.Spelling = NO -->

# BillCreatorPipelineControls mechanics

## Why subscriptionState is threaded down as a prop

BillCreatorPipelineLlm owns the live-updates connection and hands its
state down; one connection feeds both this component's paused-banner and
the panel's own refreshes.

## Why pickedBillId falls back to "run every bill"

A run covers whichever bill the page is currently on, chosen with the
shared bill picker. An empty value means "run every bill".

### `pickedBillIdFor`

The `bill_id` a new pipeline run will be started with, read off the shared
bill picker BillCreatorShell draws above the tabs.

An empty string means the picker is on its "All Bills" entry, and
usePipelineRunActions turns that into `bill_id: null`, which the server reads
as every bill.

It lives here rather than inside BillCreatorPipelineControls because two
components now need the same answer: the controls, which post it, and the
failure alert, which tells the operator what the Run pipeline button will
cover. Deriving it twice would let the two drift apart.

## Why isRunning checks every non-finished status, not just queued/running

In flight means any non-finished status — a run spends most of its life
in a stage-named status, not just "queued"/"running". Checking only those
two hid the Force-fail button mid-run.

## Why runDisabledReason is a named string, not a title= on a wrapper div

Each disabled-reason names itself here, not inferred downstream, so a
third reason later can't borrow the second's wording.

Previously this reached the button as one boolean with the reason in a
title= on a wrapper div — invisible to screen readers and to a disabled
control.

### PipelineActionButtons.test.tsx notes

Why the run button is off has to reach the operator.

It used to live in a `title` on a wrapper div. A browser does not show a
title for a disabled control, and a title on a wrapper is not a description
of the button inside it, so screen readers never announced it either. It
also covered only one of the two reasons the button can be off: deselecting
every stage greyed it out and said nothing at all.

The link between the notice and the run button is what a screen reader follows. An id on a
notice nothing points at would read as an ordinary paragraph.

### PipelineActionButtons: RUN_DISABLED_NOTICE_ID and the runDisabledReason prop

Ties the notice to the button it explains. One id, because only one run CTA
is ever on screen.

Why the run button is off, in words, or null when it is on. The caller
works this out because the caller holds the reasons; deriving it here
from `runDisabled && !isRunning` would silently label a third reason as
the second one the day somebody adds it.

## Why ForceFailDialog stays mounted when closed

Kept on the page even when closed, so it can animate shut when
forceFailOpen goes back to false.

## Why the pipeline-conflict alert avoids saying "the panel above"

Avoids "the panel above" — PipelineProgress can be showing a different,
finished run, since surfaced_pipeline_run prefers a pinned ?run_id= over
the truly in-flight one.

## Why the cable-downgrade banner needs its own isRunning gate

downgraded stays true after a run finishes — the subscription stays open
as long as remote_run_id exists (BillCreatorPipelineLlm.tsx).

isRunning gates this banner separately from the poll itself (gated on
isRunInFlight) — without it, the banner claimed a poll was running when
none was.

## Why the cable-downgrade banner overrides Alert's role to "status"

Alert defaults to role="alert"; overridden to "status" here since this is
a reconnect notice, not an assertive interruption — no native tag
replaces that without dropping the design system.

## Why ForceFailDialog requires typing the confirm phrase

The "are you sure?" dialog for force-failing a pipeline run.

Typing "force fail" exactly is a stop-and-think step, not the security
check — PipelineRunsController#force_fail re-verifies both admin and
phrase server-side.

BillCreatorPipelineControls puts this dialog on the page while a run has
not finished. The wording on it is fixed by the copy rules — do not
reword it.

## Why ForceFailDialog clears the typed phrase on any close path

Clear what was typed when the dialog closes — by Cancel, by Escape, or by
the X — so it opens empty next time.

## Why the force_fail POST sends back_to=bill_creator

back_to=bill_creator picks the post-redirect route: a run with no bill_id
lands on new_bill_creator_path(tab_key: :pipeline), one bill lands on
pipeline_bill_creator_path.

## Why ForceFailDialog needs an explicit onError

Server refusals (finished run, phrase mismatch) arrive as errors.pipeline
with no flash; onSuccess never runs, so without this the dialog looks
ignored, not refused.

## Why PipelineStageSelector gets a whole-list setter, not per-toggle calls

onSetStages is the whole-list setter. Select all/Clear all must never be
built from seven toggle calls — each arms the same delayed send, which
has already dropped a click once.

## BillCreatorPipelineControls.test.tsx notes

The alert listing stages pulled in automatically. Ticking a stage asks the server for a fresh preview,
waiting 300ms first so a run of quick clicks only causes one request.

Sits below the pipeline-conflict alert. BillCreatorPipelineLlm owns the live connection; this component
only reads `subscriptionState`.

## usePipelineRunActions notes

The old restart that wiped the cache is gone, along with its confirmation
dialog and its split menu. Restart is a single button now, and the "Download
missing assets" toggle covers what that variant used to do.

`handleResume`: the server works out which stage failed last and skips the earlier
stages whose results are already cached, so this request sends no body.

`handleRestart` must NOT send download_missing_assets. The controller checks
whether that key is present at all, and when it is missing the restart
inherits the setting from the run being restarted. Sending whatever the
toggle happens to say right now would override that inheritance, and
restart means "do again what the original run did", not "use today's
toggle".

`handleRun`'s server refusal goes through the same channel as resume and
restart. handleRun does not manage the posting flag, so it
cannot reuse postOptions.

`handleSweepStale` marks every queued or running run as failed. The rows stay in the
database for the audit trail.

`handleDeleteOrphans` is different from marking runs failed: this deletes the rows outright. The
server checks each row again before deleting it, so an out-of-date count
does no harm.
