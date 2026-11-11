---
lat:
  mode: reference
---

# GenerateBillSummaryService.call return values

`GenerateBillSummaryService#call` returns one of seven symbols.

- The controller (`BillsController#generate_summary` and `#regenerate_summary`) maps each to a redirect and a flash message; nothing downstream inspects the return value another way.

| Value | Meaning |
| --- | --- |
| `:invalid_summary_instructions` | Operator instructions for regeneration were not a string or exceeded the 2,000-character limit. The controller maps this to an Inertia generation error. |
| `:unsupported_model` | The requested model is not in `AdminSetting.offered_models`. The controller maps this to an Inertia generation error. |
| `:unsupported_reasoning_effort` | The requested reasoning effort is not one of `AdminSetting::REASONING_EFFORTS` (`low`, `medium`, `high`), or reasoning effort was supplied for a model that does not support reasoning. The controller maps this to an Inertia generation error. |
| `:no_pipeline_data` | Neither of the job's two paid LLM calls has its inputs: no source text to summarize (no on-disk diff markdown and no `bill.extracted_text` — the `diff_content` column does not count, since the prompt never renders it) and no testimony to derive positions from. The bill's pipeline has not fetched anything usable yet. |
| `:already_in_progress` | The row is `pending?` or `generating?` (for example, a double-click). A row stuck in either status past `RECLAIM_ABANDONED_AFTER` with no writer is reclaimed first, so an abandoned run cannot block the trigger forever — see summary-run-reclaim-timing.md. |
| `:enqueue_failed` | The row was armed and the queue write failed. The arm is undone before this is returned, so the row is left where the operator's next click can reach it rather than `pending` with no job coming. |
| `:enqueued` | The old run state was cleared (creating the row first if it did not exist) and the job was queued. |
