---
lat:
  mode: explanation
---

# How auto-included stages get explained in the Activity Log

`emit_state_transition!` records a run or a bill moving from one state to the next.

It is called from the "after any transition" hooks on `LegislationPipelineRun` and `PipelineRunBill`. The `state_machines` library runs those hooks inside the same database transaction as the state change, so an error raised in here undoes the state change too. The WebSocket broadcast deliberately lives in a separate after-commit hook on each model, because a broadcast must never announce a change that then gets rolled back.

## Why some transitions carry extra detail

Stages depend on each other, so `RunLegislationPipelineJob` sometimes runs a stage the operator did not tick (see `Pipeline::STAGE_DEPS`). When it does, it records why, so the Activity Log can explain itself afterwards.

## How the explanation reaches the logger

The runner passes that explanation through a per-thread holder, `Pipeline::Current.current_auto_include_context`, rather than through method arguments.

The runner fills it in just before starting the extra stage, and empties it in an `ensure` block once that stage completes. The state machine calls `emit_state_transition!` on the same thread, so the method can simply read what the runner wrote.

## What gets saved

When the event is a stage starting and the holder has something in it, three extra fields are saved with the entry:

- `:stage` — which stage was pulled in, for example `"fetch-law"`.
- `:reason` — `"missing_artifact"`, the only reason this happens today.
- `:bill_external_ids` — the bills that made it necessary.

For any other event — a stage completing, for instance — or when the holder is empty because the operator ticked the stage themselves, those fields are left out entirely, exactly as every older entry looks.

## Example payload

This example shows a `fetch-law` stage pulled in on behalf of two bills.

The statuses are the ones `LegislationPipelineRun` really uses — a run inside a stage is named for what it is doing (`"fetching_law"`), not `"running_"` plus the stage name:

```json
{
  "from": "running",
  "to": "fetching_law",
  "event": "start_fetch_law",
  "run_id": 42,
  "auto_included": true,
  "stage": "fetch-law",
  "reason": "missing_artifact",
  "bill_external_ids": ["24-1234", "24-5678"]
}
```

No new kind of event exists for this. The existing `state_transition` entry just carries more detail, and a test guards against anyone adding a dedicated stage-start event to `SEVERITY_FOR_EVENT` and `TITLE_TEMPLATES`.

## Why Pipeline::Current uses ActiveSupport::CurrentAttributes, not Thread.current

`Pipeline::Current` is the per-thread context holder described above. It is built on `ActiveSupport::CurrentAttributes` rather than a raw `Thread.current[]` lookup for three reasons:

- **One value per thread.** Solid Queue runs the orchestrator on a worker
  thread, and `CurrentAttributes` are per-thread by design, so two workers
  running at once cannot tread on each other's context.
- **Rails clears it automatically.** Rails clears `CurrentAttributes`
  between requests and jobs by calling `CurrentAttributes.reset_all` in its
  executor callbacks — the same hook that resets `Current.request`. That is
  a second line of defence in case the orchestrator's `ensure` block
  somehow fails to run.
- **It matches an existing pattern.** State-machine callbacks already drive
  logger calls this way, without tying the orchestrator to the logger.

## LegislationPipelineRun's audit-log transaction guarantee

`LegislationPipelineRun`'s `after_transition any => any` hook is what calls `sync_pipeline_run_stage` and `PipelineActivityLogger.emit_state_transition!`.

Because the `state_machines` `after_transition` callback runs inside the transition's DB transaction, a raise inside `emit_state_transition!` rolls back the whole transition — the status change never persists, and the `after_commit` broadcast hook never fires. That is the guarantee: no public state transition lands without a matching Activity Log row.

The hook skips the case where `transition.from` is `nil`. `state_machines` fires `after_transition` on the initial create too (`from: nil, to: :queued`); skipping that case keeps the audit log title (which interpolates `transition.from` into `"Run #{from} → #{to}"`) from rendering the broken-looking `"Run  → queued"`. Creation is already visible from the row's existence in the database, so no audit information is lost by skipping this entry.

The same hook mirrors each stage transition into a `PipelineRunStage` row, so the per-bill grid header can show live `stagesSucceeded` / `stagesTotal` counts. `PipelineRunStage`'s own state machine (`start_running` / `mark_succeeded` / `mark_failed`) drives that row's lifecycle, so anything reading `pipeline_run_stages` sees canonical statuses.

`#sync_pipeline_run_stage`, the private method that does this mirroring, runs from `after_transition` inside the transition's DB transaction, so a raise inside it rolls back the parent run's status write too. A transition the method does not recognize is a no-op — the audit log stays the record of truth for those.
