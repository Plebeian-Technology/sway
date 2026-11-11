---
mode: explanation
summary: "Explains why the job's completion step re-checks status under lock before marking a bill summary complete, and why it leaves llm_generated_at alone on a stand-down."
status: agent-extracted
related: []
---

# Why settle_completed re-checks status and skips llm_generated_at

<!-- vale Vale.Spelling = NO -->

`GenerateBillSummaryJob#settle_completed` is the completion tail shared by
the ordinary generate path and the re-entry path (see
[bill-summary-re-entry-guard.md](bill-summary-re-entry-guard.md)). It is
extracted into one method so the two paths cannot drift: "a correct fix
applied at ONE call site when TWO exist" is the recurring defect in this
file, and a second, hand-copied settle sequence would have been exactly
that.

## The score recompute

`RecomputeBillInterestingScoreJob` is enqueued whenever a summarization
completes and bought something (see the `recompute_score` parameter,
documented on the method itself, for the exceptions). It is enqueued with
`perform_later`, not inline, so a scoring failure never fails an
otherwise-good summary. `BillLlmProvisioning` is a separate model from
`Bill` with no natural ActiveRecord callback for "a summary just
completed" — so the hook lives here explicitly, immediately before
`mark_completed!`.

## Why mark_completed! is guarded

`mark_completed!` is guarded because the positions rescue's
`provisioning.reload` (see
[bill-summary-positions-error-handling.md](bill-summary-positions-error-handling.md))
removed insulation this call used to have. Before that reload, the row
held `generating` in memory for the whole of `#perform`, and
`state_machines` validates a transition against the IN-MEMORY value, so
`mark_completed!` could not raise no matter what another writer had done.

After a reload, it can: with no `generating -> completed` edge available,
it raises `StateMachines::InvalidTransition`, which escapes the
already-exited positions rescue, hits the catch-all, and is re-raised as
`TransientBillSummaryError` — restarting `#perform` from the top and
RE-ISSUING the paid-for summary call up to three more times. That is word
for word the outcome the positions rescue exists to prevent. (The
re-entry gate is now the backstop for that whole class: even if some
raise in this tail does restart `#perform`, the restart no longer pays
again.)

This is reachable because
`RunLegislationPipelineJob#execute_bill_level_service` calls
`GenerateBillSummaryJob.perform_now(bill.id)` inline, which bypasses
`GenerateBillSummaryService`'s `pending?`/`generating?` `with_lock` guard,
so two jobs can be in flight for one bill.

## Skipping is correct, not merely safe

A row that is no longer `generating` has already been settled by another
writer, so the end state this method wants either already holds or was
deliberately overridden. Everything worth keeping (`llm_summary`,
`full_breakdown`, citations) is committed before this method is called.

`generating?` used to be a stale in-memory read on every path except the
one that goes through the positions rescue's reload — so on the
non-testimony and successful-positions paths, the guard always passed and
this line could still overwrite another writer's settlement. Same
treatment as `#record_failure` (see
[bill-summary-failure-logging.md](bill-summary-failure-logging.md)):
re-read committed state under the write lock, decide there.
`#settle_under_lock`'s `with_lock` reloads, so `generating?` inside the
block IS the committed value.

## Why this method does not write llm_generated_at

This is a decision, not an omission. `llm_generated_at` means "when the
body on this row was produced." On the supersede path, this method
settles a run that bought nothing, so the body is still the operator's
paste and its timestamp is still the paste's. Stamping it here would
assert that a run which generated nothing generated something.

The consequence — after any later pipeline run, `diff_generated_at` is
newer and `#stale?` stays true for good — is the honest reading, not a
bug: the hand-written summary really does predate the current pipeline
data, and the operator needs that signal to decide whether to redo it.
Three other readers agree with keeping it accurate:
`ResourceCachePanelSerializer` publishes it as `last_generated_at`, which
would start reporting a stand-down as a generation; `BillCreatorLlmSummary`
keys a remount off it, so bumping it on a no-op run would discard
in-progress operator edits; and `#stale?` is the sole input to the Bill
Creator's stale header.

What WAS broken is what the UI did in that permanently-stale state:
`LlmSummaryCompletedActions` suppressed its confirmed Regenerate button on
`{!stale && ...}`, leaving the stale header's unconfirmed button as the
only control on the surface, over a body no surface identified as
hand-written. That was fixed in the UI — provenance chip, confirmed
button, pipeline gate — not by falsifying this column.

## stand_down_mid_run is the shared tail of both marker re-checks

`#stand_down_mid_run` is the shared tail of both marker re-checks (the
supersede gate's compare-and-swap and the evidence-digest compare-and-swap
— see
[bill-summary-supersede-gate.md](bill-summary-supersede-gate.md) and
[bill-summary-positions-evidence-digest.md](bill-summary-positions-evidence-digest.md)),
so the two cannot report the same event differently — the recurring
defect in this file has been one control applied at one call site when
several exist.

`recompute_score` comes FROM THE CALLER, because only the caller knows
whether this run spent anything. The persist site at
`#persist_unless_superseded!` stands down after both calls, so the score's
inputs really did move. The PRE-CALL site in
`#clear_stale_run_state_unless_superseded!` runs before `Llm::Client.build`,
so by definition it made neither call — and it became the ordinary route
for a paste that lands after the supersede gate once the arm stopped
declining there. Until then the same condition took two different
recompute decisions depending only on which side of the gate the paste
landed. The cost of getting it wrong is not a wasted write:
`RecomputeBillInterestingScoreJob` is `limits_concurrency to: 1,
on_conflict: :discard` per bill, so a genuine trigger committing while a
spurious recompute holds the lock is DROPPED.

`#settle_completed`'s own score-recompute enqueue and success log both
hang off the DECISION, not off being called. The re-check inside it can
decline — another writer settled this row while this run was in flight —
and `#settle_under_lock` also answers nil for a row that was deleted. Both
used to be followed by an unconditional success line naming the same
`provisioning_id`, so an operator or an on-call reader asking "did this
bill's summary land?" got a positive answer from a line that measured
nothing. The enqueue moved inside the decision for the same reason: a
settle that did not happen must not schedule work for itself, and the
writer that DID settle the row enqueues its own.

## The zero-adapter-calls path that still settles completed

A run that made NEITHER paid call can still reach `#settle_completed`
directly, over a row that already holds a summary — the arm above sends
every other such run to `settle_nothing_to_generate` instead. That row is
genuinely complete, so it settles `completed`, but it earns no score
recompute: the two no-summary settles state the rule ("nothing about the
bill's interestingness changed") and it is true here for the same reason.
A run that called no adapter moved none of the score's inputs (recorded
votes, active organization positions, the bill's age), and the recompute
would append a row to a table that exists to record score movement.

`clear_generation_error: true` applies on this same path — the ONE resume
that buys nothing. The rule `LlmSummaryPositionsErrorNotice` reads is that
a completed row's `generation_error` can only have come from the
positions rescue, and the pre-call clear is what used to hold that up. A
positions-only resume deliberately SKIPS that clear, to keep the purchase
marker, and the compensating clear that rides on the positions persist
instead covers every such resume except the one where the evidence goes
away between `#positions_owed?` and the locked read below it, leaving
nothing to buy and no persist to run. That row settled `completed` still
carrying the previous attempt's `record_failure` message, and the notice
told the operator the positions call had failed and the drafts on screen
were from an earlier run — over a row with no drafts at all. The clear
sits inside `#settle_completed`'s own committed-state re-check, so it
cannot erase a notice another writer left on a row it settled while this
run was away.

## positions_persisted vs positions_attempted: which one gates the recompute

The `recompute_score` argument at the ordinary end of `#perform` passes
`positions_PERSISTED`, not `positions_attempted`. The score reads recorded
votes, ACTIVE organization positions and the bill's age. A positions call
that raised into the rescue, or whose persist was declined
`:evidence_withdrawn`, wrote none of them — its only write to the row was
an error string. This file states the narrower rule three times ("nothing
about the bill's interestingness changed"), and this was the one site
where the stated rule and the code disagreed.

The cost of the wider predicate is not a wasted write.
`RecomputeBillInterestingScoreJob` is `limits_concurrency to: 1,
on_conflict: :discard` per bill, so a spurious enqueue holding the lock
DROPS a genuine trigger committing beside it — an operator approving an
organization position on the same bill, say. Both real triggers already
enqueue their own recompute on write (`LegislatorVote` and
`OrganizationBillPosition`), so this one can only ever be the spurious
enqueue that discards theirs.
