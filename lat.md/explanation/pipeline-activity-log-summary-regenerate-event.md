---
lat:
  mode: explanation
---

# Why one event covers "generate" and "regenerate"

One kind of event, `summary_regenerate_triggered`, covers two different situations: the "Generate summary" button on a bill with no summary yet, and the "Regenerate summary" button on a bill that already has one.

Both buttons send the same request, so `PipelineActivityLogger` cannot tell them apart from the request alone.

The title tells them apart instead. `TITLE_TEMPLATES` builds a title that names the bill (so the row makes sense in the Activity Log without being expanded) and says which case it was, so a first-ever summary is never described as a regeneration.

`PipelineActivityLogger.log_summary_regenerate_triggered!` takes a `first_generation` boolean to drive that title. This value is true when the bill had no summary at all before the request. Only the caller can supply it, because only the caller sees the bill's record before anything changes it — by the time the logger runs, that information is gone.

`GenerateBillSummaryService` calls this method on its regenerate path, reached from `BillsController#regenerate_summary`. The entry is filed against the bill, so the Activity Log can filter and link entries by bill.
