---
mode: explanation
summary: "Why BillProcessingError exists as the one error every pipeline stage raises for a single-bill failure, letting the orchestrator set pipeline_run_bills.status without knowing every stage's exception classes."
status: agent-extracted
related: [docs/explanation/generate-diffs-service-design.md, docs/explanation/hearing-fetch-pipeline.md, docs/explanation/pipeline-run-failure-handling.md, docs/reference/stages-to-run-algorithm.md]
---

<!-- vale Vale.Spelling = NO -->

# Why `BillProcessingError` exists

`BillProcessingError` is the one error every pipeline stage raises when a
single bill fails: `FetchBillsService`, `ExtractTextService`,
`ParseSectionsService`, `GenerateDiffsService`, `FetchLawService` and
`FetchHearingsService`.

A stage catches what went wrong for one bill — a `Faraday::Error`, a
`JSON::ParserError`, a file read or write error — and re-raises it as a
`BillProcessingError` with a short message. The code running the pipeline
can then set `pipeline_run_bills.status` without every exception class
from inside a stage leaking out into it.

See [Stages-to-run algorithm](../reference/stages-to-run-algorithm.md) for
how the per-bill failure budget counts these, and
[GenerateDiffsService: ResultWriter](generate-diffs-service-design.md#resultwriter-why-a-disk-failure-becomes-billprocessingerror-not-a-run-killing-error)
and [The hearing-fetch pipeline](hearing-fetch-pipeline.md#why-an-unexpected-write-failure-becomes-billprocessingerror)
for two examples of a stage turning a lower-level failure into this class.
