---
lat:
  mode: explanation
---

# What PipelineActivityLogger does

`PipelineActivityLogger` is the one place anything in the legislation pipeline records what just happened, for every kind of event.

It does four things:

- Builds the details hash for the kind of event being recorded.
- Writes one `PipelineActivityLogEntry` row inside a transaction.
- Once that transaction has committed, sends the entry to the operator:
  attached to the page response when the current request is about to
  render a page (the flash rides along to React), or over a WebSocket in
  every other situation — background jobs, webhook receivers, JSON error
  responses, and so on.
- Catches any delivery failure, so a failed banner or broadcast can never
  undo the row that was already saved.

Callers never choose the severity or the title of an entry. Severity comes from `SEVERITY_FOR_EVENT` and the title from `TITLE_TEMPLATES`, both keyed by the kind of event. `serialize_entry` is public because the code that loads the Activity Log page reuses the same shape. Timestamps go out with microsecond precision.

## How the logger knows whether a page is about to render

`ApplicationController` stores the current request in a per-request thread-local (`Current.request`), via a `before_action { Current.request = request }`.

`PipelineActivityLogger` reads that to decide whether to deliver a message synchronously (attached to the flash on the page about to render) or asynchronously (over ActionCable) — it has no other way to know whether the code calling it is running inside a request that is about to render a page.

`Current` (`ActiveSupport::CurrentAttributes`) is used for this rather than a plain `Thread.current[]`, because `CurrentAttributes` clears itself between requests automatically — a bare `Thread.current[]` value would leak into the next request handled by the same thread (Puma reuses threads across requests) unless every code path remembered to clear it.

### The end-to-end request spec proving the flash round-trip (HIGH-R2-3)

`spec/requests/pipeline_activity_logger_inertia_flash_spec.rb` follows a flash message the whole way through a real request.

`spec/requests/pipeline_activity_logger_inertia_flash_spec.rb` follows a flash message the whole way through a real request: it shows that calling `PipelineActivityLogger.log_*!` inside an action that renders through Inertia ends up as `usePage().props.flash.activity_log_entry` in the response. Nothing about the request is stubbed — the real Rails flash, the real shared `flash:` prop, and the real Inertia renderer are all exercised. It sends the `X-Inertia` header along with the server's current asset version, so Inertia's middleware does not answer 409 for a version mismatch; inside the action `Current.request.inertia?` is then true, which is what makes `PipelineActivityLogger` take its synchronous flash route rather than the asynchronous ActionCable one described above.

## How PipelineActivityLogEntry triggers delivery

`PipelineActivityLogger::Transport.dispatch` pushes an entry out over ActionCable and writes the Inertia flash message.

That should happen only after the surrounding transaction — the one that created the row, often a `state_machines` `after_transition` callback — actually commits. Otherwise subscribers can be shown state that later rolls back.

`PipelineActivityLogEntry` triggers this with `after_commit :dispatch_pipeline_activity_transport, on: :create`, which fires at exactly that moment: once the outermost transaction around the row's INSERT commits. When the entry is created outside any transaction, `after_commit` still runs straight away, so the controller path behaves the same as before.

`#dispatch_pipeline_activity_transport` rescues any error from `Transport.dispatch` so a transport failure — ActionCable down, a frozen flash hash — never escapes `after_commit` and damages unrelated Rails machinery further up the call stack. The warning it logs carries the whole entry (id, event_type, subject) so an operator reading Rails.log can tie a quiet dispatch failure back to the audit-log row it came from. `Transport.dispatch` already logs per branch and surfaces flash errors on the Inertia path; this outer rescue only catches what it could not handle itself, such as a serialization bug raising before its own rescues get a chance.

## Why delivery is triggered by an after-create hook, not a hand-written dispatcher

Rails' own "run this once the transaction commits" machinery is well tested and keeps working across Rails upgrades.

An earlier hand-written dispatcher class had to second-guess how Rails 8.1 manages transactions and could blow up with a missing-method error on some database adapters. See `app/models/pipeline_activity_log_entry.rb#dispatch_pipeline_activity_transport`.

## Why certain events carry a fixed severity

Callers never choose severity, and three of the choices baked into `SEVERITY_FOR_EVENT` are not obvious from the event name alone:

- `summary_regenerate_triggered` is `"info"`. An operator asking for a
  summary is just news, not a problem. The button queues
  `GenerateBillSummaryJob`; the entry is the record that they pressed it.
- `state_transition` and `bill_state_transition` are `"info"`. A run or a
  bill moving from one state to the next is recorded from the "after any
  transition" hook on `LegislationPipelineRun` and `PipelineRunBill`. Moving
  states is neutral in itself, so it is only news. Events that mean
  something went wrong (`stage_failed`, `force_fail_triggered`) carry their
  own harsher severity.
- `stage_budget_tripped` is `"warning"`. Five bills in a row failed, so
  `RunLegislationPipelineJob` gave up on the stage. A warning rather than an
  error, because raising will move the run into its own "`<stage>` failed"
  state, which speaks for itself.

## Why log_org_position_decision! accepts a duck-typed draft

`draft` can be any object that answers `.id` and `.organization_name`.

The model behind the org-position-decision screen is not settled yet, so rather than demanding a specific class the method takes whatever responds to those two, and stores the organization name and the decision in the entry.

## Why the org-position decision carries an extra payload

`log_org_position_decision!` takes an optional `extra:` hash that is merged into the entry's payload. It exists so `decision` can stay a small, enumerable set of values.

The alternative was tried first and rejected. A campaign approval that replaces an earlier decision needs to record WHICH draft it replaced, and the quickest way to do that is to append the draft's hash to the decision string — `approved_replacing_draft_grp1`. That gives an otherwise enum-shaped field unbounded cardinality: anything matching `decision` by equality silently stops matching, and grouping the log by decision produces one bucket per draft.

So a caller with a variable to store puts it in its own key. `decision` stays something you can filter on.

## Transport: two delivery paths, and safety nets for both

There are two ways to get a freshly written activity-log entry in front of the operator, and `PipelineActivityLogger::Transport` picks one.

There are two ways to get a freshly written activity-log entry in front of the operator, and `PipelineActivityLogger::Transport` picks one: attach the entry to the page response Rails is about to render, or push it down a WebSocket to whoever is watching. It also holds the safety nets for when either fails, and the logic that works out which WebSocket channel to send to.

`PipelineActivityLogEntry` calls this from its after-create hook. That hook wraps this in its own rescue, so a delivery failure can never escape and damage unrelated work. The rescues inside `Transport` exist for a different reason: to make sure the operator sees SOMETHING — an error banner, or a warning in the log — when delivery fails.

## Transport: why delivery must stay on the request's own thread

Rails runs the after-save hook on the same thread that saved the record, so `Current.request` still holds the request that started all this.

Delivery must never move onto another thread or into a background job: that thread would see no request, and the "attach to the page response" path would silently stop working.

## Transport: why dispatch_async also writes a log line

When there is no page to attach to — a webhook, a JSON error response, a background job, or a service — the entry goes out over ActionCable instead.

It also writes a line to the log. When the pipeline is run straight through from a rake task, a seed script, or the console, nobody is listening on the WebSocket, so the message vanishes and the operator watches a silent terminal for five to ten minutes. The log line gives them a heartbeat; the full details stay in the database row for the web UI to display.

## Transport: why inertia_request? has its own rescue

`inertia_rails` 3.21.0 and later add an `inertia?` method to the request object, and the version this repo locks to has it. The rescue is there in case a future version takes it away again.

## Why a run failure must write an error-severity entry, checked by severity

`handle_run_failure` used to leave the Activity Log with only an "info" severity `state_transition` row — an operator filtering the log for errors saw a clean log over a failed run.

`spec/jobs/run_legislation_pipeline_job_spec.rb` covers this by querying `PipelineActivityLogEntry.errors_only`, filtering BY severity rather than by `event_type`. A query that filtered by `event_type` and then read severity back could never fail: `emit!` sets severity from a fixed map keyed on `event_type`, so that assertion shape would only be reading back its own input.

## Why the run still reaches "failed" when the Activity Log write itself raises

A regression let `log_stage_failed!` run BEFORE the terminal state transition.

Its own rescue swallows `ActiveRecord::ActiveRecordError`, so a busy database on that write could block the run from ever reaching `"failed"`. The spec forces that same error (stubbing `PipelineActivityLogger.log_stage_failed!` to raise `ActiveRecord::StatementInvalid`) and asserts the run still reaches `"failed"`.

## Why the frontend suppresses toasts for bill_state_transition but not state_transition

`bill_state_transition` fires pending→running→succeeded for EVERY bill in a run, often more than 100 toasts, which buries the admin.

`subscribeActivityLog` (`app/frontend/channels/activityLogChannel.ts`) skips the toast for it; the entry still lands in the Activity Log panel on the page, through `onAppend`. The run-level `state_transition` event is deliberately NOT skipped: roughly 14 per run, one at the start and end of each stage (for example "Run running → parsing_sections"). That is the quiet "which stage is the pipeline in" signal. Everything else — admin actions, warnings, errors — keeps toasting.

## Why failure payloads cap error strings at 4000 characters

[[app/services/pipeline_activity_log/ingestion_failure_payload.rb#IngestionFailurePayload]], [[app/services/pipeline_activity_log/llm_json_parse_failure_payload.rb#LlmJsonParseFailurePayload]], [[app/services/pipeline_activity_log/llm_provider_error_payload.rb#LlmProviderErrorPayload]], and [[app/services/pipeline_activity_log/stage_failure_payload.rb#StageFailurePayload]] cap error strings and raw response excerpts at 4000 characters because activity-log rows are retained indefinitely and unbounded strings would bloat the table.
