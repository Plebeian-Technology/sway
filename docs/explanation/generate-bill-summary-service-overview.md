---
mode: explanation
summary: "Explains what GenerateBillSummaryService owns, why it was extracted from the controller, and how generate and regenerate differ."
status: agent-extracted
related: [docs/reference/generate-bill-summary-service-outcomes.md]
---
<!-- vale Vale.Spelling = NO -->

# What GenerateBillSummaryService owns

The service decides whether a bill's LLM-written summary can be generated
or regenerated, and queues the job when it can. It was extracted from
`BillsController#generate_summary` and `#regenerate_summary`, which shared
the same guard-then-enqueue body. The service owns the business
logic: the two preconditions (pipeline data present, no generation already
in flight), clearing stale run state, the enqueue, and, on regenerate, the
audit-log entry. The controller only maps the returned symbol (see
[../reference/generate-bill-summary-service-outcomes.md](../reference/generate-bill-summary-service-outcomes.md))
to the per-action redirect and copy.

## What `regenerate:` changes

The `regenerate:` flag selects the two behaviors that differ between the
generate and regenerate actions:

- Regenerate writes its audit entry AFTER the enqueue commits, so the entry
  only exists when everything before it succeeded ("log last").
- Both paths share ONE `supplemental_testimony` rule: a blank value leaves
  the column alone, and clearing requires an explicit flag. The old split —
  generate always wrote the column, regenerate wrote it only when supplied —
  meant a body-less generate wiped an operator's pasted testimony, and a
  stale browser tab's `""` could wipe one on regenerate too.
