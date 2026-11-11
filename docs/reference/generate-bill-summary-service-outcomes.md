---
mode: reference
summary: "Documents the four symbols GenerateBillSummaryService#call can return and what each tells the caller."
status: agent-extracted
related: [docs/explanation/generate-bill-summary-service-overview.md]
---
<!-- vale Vale.Spelling = NO -->

# GenerateBillSummaryService#call return values

`GenerateBillSummaryService#call` returns one of four symbols. The
controller (`BillsController#generate_summary` and `#regenerate_summary`)
maps each to a redirect and a flash message; nothing downstream inspects
the return value another way.

| Value | Meaning |
| --- | --- |
| `:no_pipeline_data` | Neither of the job's two paid LLM calls has its inputs: no source text to summarize (no on-disk diff markdown and no `bill.extracted_text` — the `diff_content` column does not count, since the prompt never renders it) and no testimony to derive positions from. The bill's pipeline has not fetched anything usable yet. |
| `:already_in_progress` | The row is `pending?` or `generating?` (for example, a double-click). A row stuck in either status past `RECLAIM_ABANDONED_AFTER` with no writer is reclaimed first, so an abandoned run cannot block the trigger forever — see [summary-run-reclaim-timing.md](../explanation/summary-run-reclaim-timing.md). |
| `:enqueue_failed` | The row was armed and the queue write failed. The arm is undone before this is returned, so the row is left where the operator's next click can reach it rather than `pending` with no job coming. |
| `:enqueued` | The old run state was cleared (creating the row first if it did not exist) and the job was queued. |
