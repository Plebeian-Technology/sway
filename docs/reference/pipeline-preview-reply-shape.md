---
mode: reference
summary: "Catalogs the six keys PipelinePreviewService#fetch returns and what each one holds."
status: agent-extracted
related: [docs/explanation/pipeline-preview-service-design.md]
---
<!-- vale Vale.Spelling = NO -->

# PipelinePreviewService's reply shape

For why the service is built the way it is, see
[pipeline-preview-service-design.md](../explanation/pipeline-preview-service-design.md).
This document catalogs the hash `PipelinePreviewService#fetch` returns, or
`nil` when nothing was selected (`BillsController` relies on that `nil` to
stop early when `?stages=` is empty).

| Key | Type | Holds |
|---|---|---|
| `stages_requested` | `Array<String>` | What the operator ticked, echoed back. |
| `stages_will_run` | `Array<String>` | Those plus anything pulled in, in run order. |
| `stages_auto_included` | `Array<String>` | Only the extras that were pulled in. |
| `confirmation_required` | `Boolean` | True when anything was pulled in. |
| `confirmation_message` | `String?` | Set only when `confirmation_required` is true. |
| `prereq_violations` | `Array<Hash>` | Stages that will fail for want of inputs. |

The first five keys are fixed — how they are worked out has changed, but
their names and meanings have not. `prereq_violations` was added later,
alongside them, to feed the warning the stage picker shows; it never
replaced any of the original five.

`PipelinePreviewService` fills `prereq_violations` in when the "Download missing assets" toggle
is off, and leaves it empty otherwise. `PipelineStageSelector` (the frontend's `IPipelinePreview`
type) shows one warning line per entry.

Each entry in `prereq_violations` is one stage-and-missing-prerequisite
pair:

| Field | Holds |
|---|---|
| `stage` | The ticked stage that will fail. |
| `prerequisite` | The dependency it is missing. |
| `missing_artifact` | The column or file name a reader would look for (see `PipelinePreviewService::MISSING_ARTIFACT_TOKENS`). |
| `bill_count` | How many bills in scope lack that prerequisite. |
