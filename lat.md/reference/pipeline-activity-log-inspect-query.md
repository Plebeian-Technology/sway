---
lat:
  mode: reference
---

# PipelineActivityLogEntry.inspect_query

`#inspect_query` builds an ActiveRecord query, as text, for an operator to copy out of the activity log panel and paste into a console.

- Looking at a log entry, they usually want the record behind it in one step: the `OrganizationBillPosition` an approval created, the `BillLlmProvisioning` that produced a summary, the `LegislationPipelineRun` that changed state.

## Query text per event type

Lookup queries and inspection parameters associated with each pipeline activity log event type.

| `event_type` | Returned query |
|---|---|
| `org_position_decision` | `OrganizationBillPosition.joins(:organization).where(bill_id:, organizations: {name:})` |
| `paste_summary_accepted`, `paste_summary_rejected` | `BillLlmProvisioning.where(bill_id:).order(updated_at: :desc).first` |
| `force_fail_triggered`, `state_transition` | `LegislationPipelineRun.find(run_id)` |
| `orphan_run_deleted` | `LegislationPipelineRun.where(id: run_id)`, commented that the run is destroyed and history lives in `pipeline_activity_log_entries` |
| `bill_state_transition` | `PipelineRunBill.find(bill_run_id)` |
| anything else | `PipelineActivityLogEntry.find(id)` — the entry itself |

## Where payload keys come from

`PipelineActivityLogger` decides what each event puts in `payload`.

- See `#log_org_position_decision!`, `#log_paste_*!`, `#log_force_fail_triggered!`, `#log_orphan_run_deleted!`, `#emit_state_transition!`, and `#emit_bill_transition!` for the key names each event type writes.

## Output invariants

Sanitization, quote escaping, and formatting guarantees required for inspected log event output.

- Payload values come from people (an operator's email, an organization
  name), so string values go through `#inspect` to escape any quotes inside
  them. The returned text has to parse as valid Ruby; a spec checks that
  with `RubyVM::AbstractSyntaxTree.parse`.
- `payload` is stringified with `deep_stringify_keys` before use, so the
  keys look the same whether the payload is still in memory (symbol keys) or
  has been through the database as JSON (string keys).
  `PipelineActivityLogger#serialize_entry` does the same normalization.
