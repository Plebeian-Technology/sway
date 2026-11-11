---
lat:
  mode: explanation
---

# Pipeline failed-stage display

`failedStageInfo` works out which stage of a pipeline run failed, and how to describe it.

It trusts the run's own per-stage rows first. If none of them is marked failed, it falls back to where the run's current stage sits in the stage list. When neither answers, the number comes back null, so the screen says "Failed during pipeline" instead of the misleading "stage 0".

`PipelineFailureHeader` is the failure banner for a failed single-bill run. When it cannot work out which stage number failed, it says "Failed during pipeline" instead of the misleading "Failed at stage 0".

(`app/frontend/components/admin/creator/pipeline-controls/failedStageInfo.ts`, `app/frontend/components/admin/creator/pipeline-controls/PipelineFailureHeader.tsx`)

## Why PipelineResumeActions dropped the old split button

The old split button with its dropdown arrow, its extra restart menu item and its confirmation dialog are all gone. The "Download missing assets" toggle on the Stages card covers that ground now.
