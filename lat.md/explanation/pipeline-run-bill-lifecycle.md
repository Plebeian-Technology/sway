---
lat:
  mode: explanation
---

# PipelineRunBill lifecycle decisions

Explains why PipelineRunBill#sort_order is write-once, why the unused mark_skipped event stays, and why started_at/finished_at are stamped inside the status state machine's before_transition hooks.

## Why sort_order cannot change once set

`sort_order` must never change once the row exists — the per-bill grid treats it as each bill's fixed place.

`FetchBillsService#seed_ar_rows` sets it only on create, and `validate :sort_order_monotonic, on: :update` pins that rule down against a future callback or service quietly updating it.

`update_columns` deliberately bypasses this (it skips all validations), for a one-off data-fix rake task or a future drag-to-reorder control. Anyone using that escape hatch must write the audit event by hand (`PipelineActivityLogger`), since the automatic one is skipped too. This is pinned by `spec/models/pipeline_run_bill_spec.rb`, "permits update_columns(...)".

## Why mark_skipped stays despite no caller

No caller invokes `mark_skipped!` today — the orchestrator only ever marks a bill row `succeeded` or `failed`.

The event is kept because `:skipped` is part of the declared status enum this state machine owns; deleting the event would leave that value reachable only by a raw column write outside the state machine.

## Why started_at/finished_at are stamped inside before_transition

The `before_transition any => :running` and `before_transition any => \[:succeeded, :failed, :skipped]` hooks stamp `started_at` and `finished_at` so the write rides along in the same UPDATE that changes `status`.

The `before_transition any => :running` and `before_transition any => \[:succeeded, :failed, :skipped]` hooks stamp `started_at` and `finished_at` so the write rides along in the same UPDATE that changes `status` — one round trip that can't come apart, picked up by the next partial reload. Before this, `started_at`/`finished_at` were never written despite the table, model, and serializer all expecting them.

## The after_transition and after_commit hooks follow the run-level pattern

`PipelineRunBill`'s `after_transition any => any` hook runs inside the transition's transaction — if `emit_bill_transition!` raises, the transition rolls back and the `after_commit` broadcast below never fires.

It skips the unspoken `from: nil, to: :pending` transition at create time the same way `LegislationPipelineRun` does (see [[docs/explanation/pipeline-activity-log-auto-included-stage-context.md|pipeline-activity-log-auto-included-stage-context.md]]).

The `after_commit on: :update` broadcast hook fires only after commit and only when `status` changed, so `update_columns(stage_results: …)` — how per-stage successes are tallied — never triggers a broadcast. It goes through `PipelineRunBroadcast` for the same reason `LegislationPipelineRun#broadcast_status_change` does (see [[docs/explanation/legislation-pipeline-run-broadcast-status-change.md|legislation-pipeline-run-broadcast-status-change.md]]): an exception in the send travels back to whoever saved the row, which here is the pipeline job, rather than failing the transaction.

## Why after_transition any => any needs a steep:ignore

The `after_transition any => any` hook needs `steep:ignore` because the `state_machines` gem's `any => any` DSL is not modeled in the RBS shim (`sig/shims/external_auth_libs.rbs`).

The `after_transition any => any` hook needs `steep:ignore` because the `state_machines` gem's `any => any` DSL is not modeled in the RBS shim (`sig/shims/external_auth_libs.rbs`) — the shim types the block param as `ApplicationRecord`, not `PipelineRunBill`. `LegislationPipelineRun`'s own `after_transition` hook needs the same ignore for the same reason.

## Why LegislationPipelineRun's pipeline_run_bills association orders by sort_order

`pipeline_run_bills` rows must always come back in `bill.id` order, which lines up with `sort_order`.

Resuming a run or retrying only the failed bills inserts `PipelineRunBill` rows out of that order, so `LegislationPipelineRun`'s `has_many :pipeline_run_bills` association carries a default `-> { order(:sort_order) }` scope. That keeps the JSON output and the per-bill grid UI in the right order no matter what order the rows were inserted in.
