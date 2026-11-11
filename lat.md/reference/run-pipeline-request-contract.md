---
lat:
  mode: reference
---

# POST /bills/run_pipeline request contract

The parameters an operator can send when starting a pipeline run:

1. The field is called `download_missing_assets` now; the old `refresh`
   field is gone and is silently ignored if a caller still sends it. This
   followed the usual pattern of adding the new column first, moving all
   the reads and writes over, then removing the old one — the same reason
   `LegislationPipelineRun#to_builder` no longer outputs `refresh` at all;
   `download_missing_assets` is the only toggle serialized now.
2. If both fetch stages are selected, the server force-computes
   `download_missing_assets` to `true` regardless — even for a
   hand-written request that sets it to `0`. That decision is made on the
   server, not only in the browser.
3. Seven stage names are accepted rather than five: `fetch-law` and
   `summarize-bill` joined the original list.

- See [[docs/reference/stages-to-run-algorithm.md|Stages-to-run algorithm]] for what happens to these stage names once the job runs, and [[docs/explanation/legislation-pipeline-stage-list-naming-and-order.md|Why the pipeline stage list has this name and this order]] for the canonical stage list itself.
