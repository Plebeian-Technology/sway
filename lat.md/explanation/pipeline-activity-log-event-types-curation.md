---
lat:
  mode: explanation
---

# Why four event types are not in EVENT_TYPES

A curation pass removed four candidate names from `PipelineActivityLogEntry::EVENT_TYPES`: `llm_timeout`, `paste_back_validation_failure`, `force_fail`, and `orphan_deletion`.

Nothing in `app/` or `lib/` ever emitted any of them, and reintroducing any of the four would recreate a problem the removal fixed.

## Two were duplicate spellings of real events

`force_fail` and `orphan_deletion` were second spellings of events the code does emit: `force_fail_triggered` and `orphan_run_deleted`.

The duplicates were recorded at a different severity than the real events, so an operator filtering the activity log by severity would have been told two different things about the same underlying event.

## Two named distinctions the LLM layer cannot draw

`llm_timeout` and `paste_back_validation_failure` named failure modes finer than what the code can actually detect:

- The LLM adapter layer raises only `Llm::TransportError` and
  `Llm::SchemaError` — nothing tells a timeout apart from any other
  transport failure, so `llm_timeout` had nothing to distinguish it from
  the existing `llm_provider_error`.
- `paste_summary_rejected` already covers a refused paste, so
  `paste_back_validation_failure` named a case the existing event type
  already handles.
