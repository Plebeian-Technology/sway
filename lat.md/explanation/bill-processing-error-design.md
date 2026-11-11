---
lat:
  mode: explanation
---

# Why BillProcessingError exists

`BillProcessingError` is the one error every pipeline stage raises when a single bill fails: `FetchBillsService`, `ExtractTextService`, `ParseSectionsService`, `GenerateDiffsService`, `FetchLawService` and `FetchHearingsService`.

A stage catches what went wrong for one bill — a `Faraday::Error`, a `JSON::ParserError`, a file read or write error — and re-raises it as a `BillProcessingError` with a short message. The code running the pipeline can then set `pipeline_run_bills.status` without every exception class from inside a stage leaking out into it.

See [[docs/reference/stages-to-run-algorithm.md|Stages-to-run algorithm]] for how the per-bill failure budget counts these, and [[docs/explanation/generate-diffs-service-design.md|GenerateDiffsService: ResultWriter]] and [[docs/explanation/hearing-fetch-pipeline.md|The hearing-fetch pipeline]] for two examples of a stage turning a lower-level failure into this class.
