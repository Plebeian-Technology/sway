---
lat:
  mode: explanation
---

# Reclaiming an abandoned summary run

`BillLlmProvisioning#reclaimable?` is true when a row is stuck in a non-terminal status with no live writer, so a fresh run may take it over.

## The one definition of that judgement

This judgement used to exist only inside `GenerateBillSummaryService#reclaim_abandoned_run!`, which runs in exactly one place: on a Generate or Regenerate click.

Every control that posts to those is disabled while the row is `pending` or `generating`, so the recovery could only be reached by an operator who did not need it.

A row a dead worker left `generating` on a bill with NO prior summary had no exit at all. The panel renders a disabled button for that status with no condition on it, and the stale header — the other place a Regenerate button lives — cannot appear either, because `#stale?` needs `llm_generated_at`, and a row that never produced a summary has none. The only ways out were a full pipeline run over the whole locale or a Rails console.

The judgement is therefore published: it goes out on the provisioning prop, and `ReclaimAbandonedSummaryRunsJob` sweeps on it. A guarantee that a row never strands cannot rest on a client choosing to offer a button.

## nil updated_at is NOT reclaimable

Every row this application writes has an `updated_at`, so a `nil` means the row was built outside the ordinary path, and "unknown" must not read as "free" — the same rule `SummaryRunArmDecision#abandoned?` applies.

## Which writer owns a reclaimable row

`BillLlmProvisioning#to_builder` also sends `paste_owns_summary_run` (`SummaryRunMarker.operator_paste?(summary_run_id)`), a different question from who wrote the body standing on the row.

`BillLlmProvisioning#to_builder` also sends `paste_owns_summary_run` (`SummaryRunMarker.operator_paste?(summary_run_id)`), a different question from who wrote the body standing on the row — that second question is answered by `llm_provider`. `paste_owns_summary_run` is the question the reclaim sweep branches on: `SummaryRunRelease.call`, over a caller that re-arms nothing, diverts a `#reclaimable?` row carrying an operator-paste marker to `.hand_off_paste!`, which keeps the text and walks the row to `completed`, and writes neither release message.

### Why llm_provider alone got this wrong

The two columns disagree on an ordinary path.

Generate and Regenerate write `summary_run_id: nil` and leave `llm_provider` alone — the clear is the supersede itself (`GenerateBillSummaryService`), and `SummaryRunMarker` explains at length why neither column can do the other's job. As a result a row that was pasted into and then regenerated still reads `"operator_paste"` in `llm_provider` while carrying no marker in `summary_run_id`, and the sweep releases it with a message rather than diverting. `LlmSummaryInFlightNotice` used to ask `llm_provider`, so it told exactly that operator to sit and wait for a settle that was never coming. It asks `paste_owns_summary_run` instead.

`paste_owns_summary_run` is a derived boolean rather than the raw column, because `summary_run_id` also carries values that are not pastes, and telling the shapes apart is `SummaryRunMarker`'s job rather than the browser's.

## Why ReclaimAbandonedSummaryRunsJob exists

`ReclaimAbandonedSummaryRunsJob` frees bill summary rows that a dead worker left in a non-terminal status.

`GenerateBillSummaryService` owns the reclaim, and it runs in exactly one place: inside a Generate or Regenerate click. Every control that posts to those is disabled while the row is `pending` or `generating`, so the recovery could only ever be reached by an operator who did not need it.

For most rows a second door existed — the stale header carries a Regenerate button. It cannot open for the case that matters: `BillLlmProvisioning#stale?` requires `llm_generated_at`, and a row that never produced a summary has none. So a bill with NO prior summary, whose worker died mid-run (the Pi runs out of memory, a deploy lands, kamal restarts mid-call — all routine on a single Raspberry Pi), sat `generating` forever. Its only exits were a full pipeline run over the whole locale, re-paying for every other bill in it, or a Rails console.

The table `SummaryRunArmDecision` documents lists "a row must never strand with no way out" as one of five invariants each paid for by an earlier defect. A guarantee whose only enforcement is a client choosing to render an enabled button is not a guarantee. This sweep is the server-side enforcement; the published `reclaimable` prop is what lets the surface offer the exit sooner, and neither depends on the other.

**What it does NOT do.** It makes no LLM call and enqueues no job. It moves a stranded row to a status the operator's own controls can act on, and stops. Deciding to spend money again stays with the operator.

`SummaryRunRelease` owns what "moves" means, including the case where the row carries a summary a human pasted and the promised hand-off is what is owed.

It is registered as a Solid Queue recurring task in `config/recurring.yml`, and it runs in development too: it is a pure database sweep with no external coupling, the same reason `PipelineActivityLogCleanupJob` runs there.

## Why reclaim narrows in SQL first, then re-checks under the lock

`ReclaimAbandonedSummaryRunsJob#perform` narrows candidates in SQL first so the sweep does not load every provisioning row.

`#reclaimable?` is still consulted per row under the lock in `#reclaim` — inside `SummaryRunRelease` — because it is the one definition of the judgement and the row may have moved between this query and the lock. The lock reloads, so `SummaryRunRelease`'s re-check runs on COMMITTED state: a run that woke up and wrote the row between the query and this line is left alone — the same argument as every other re-check in this subsystem.

Inside the lock, `status_before` and `abandoned_since` are read before the transition: both describe the row the sweep FOUND, and the transition rewrites `updated_at`.

`SummaryRunRelease` owns the transition, and it is told this caller does not re-arm (`rearmed_by_caller: false`). That is what makes it write a message the operator can read and finish a paste hand-off instead of failing it. Spelling the two edges out again at the call site is how those guarantees were lost the first time.

## Why the paste-hand-off spec asserts be_nil alone, not a pair of release constants

`spec/jobs/reclaim_abandoned_summary_runs_job_spec.rb`'s divert example asserts `provisioning.generation_error` `be_nil`, and only that — not also that it excludes neither of the two `SummaryRunRelease` message constants.

`be_nil` is the stronger claim of the two: the divert path writes no message at all, not merely neither of the release constants. The pair form was argued for once as catching a later branch that started writing one of the release messages on this path — but every value that would fail the pair also fails `be_nil`, so the pair could never be the assertion that actually caught a regression. An assertion with no case of its own to catch is worth deleting, not keeping alongside a stronger one.
