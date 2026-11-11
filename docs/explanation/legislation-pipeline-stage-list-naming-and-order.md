---
mode: explanation
summary: "Explains why ALLOWED_PIPELINE_STAGES was renamed from its old, misleading name and why fetch-law must run second."
status: agent-extracted
related: []
---
<!-- vale Vale.Spelling = NO -->

# Why the pipeline stage list has this name and this order

`LegislationPipelineRun::ALLOWED_PIPELINE_STAGES` is the canonical list of
pipeline stages, in run order. It originally mirrored the
`ALLOWED_PIPELINE_STAGES` list in the old Python service's stage registry.

## The rename

`summarize-bill` is a first-class stage that operators can pick like any
other. The constant used to be called `FULL_NON_SUMMARY_STAGES`, which
wrongly implied that `summarize-bill` was excluded from it. It was renamed
to `ALLOWED_PIPELINE_STAGES` to match the controller's
`PIPELINE_STAGE_KEYS`.

## Why fetch-law runs second

`fetch-law` sits right after `fetch-bills`, ahead of every other stage, so
that `LawSection` rows exist before `parse-sections` runs. `parse-sections`
needs those rows to resolve section references. Moving `fetch-law` later in
the list would break that resolution.

## The class-load check tying PHASE_52_STAGE_STATES to STAGE_STATUS_TO_DAG_NAME

`PHASE_52_STAGE_STATES` and `STAGE_STATUS_TO_DAG_NAME` are two parallel
lists declared on `LegislationPipelineRun`. A check in the class body
(model lines 148-155) raises at class-load time if any
`PHASE_52_STAGE_STATES` symbol is missing its `STAGE_STATUS_TO_DAG_NAME`
entry, stopping a future contributor from adding an 8th stage state
without a matching mapping entry — a gap that once caused a stage row to
get stuck and never reset.

Because the check only runs when the class loads, it cannot be re-run
against a live class to prove it actually catches a missing entry.
`legislation_pipeline_run_spec.rb`'s "STAGE_STATUS_TO_DAG_NAME class-load
integrity check" pins two things together: that the constants as shipped
today pass the check, and that running the same check logic against a
copy of the mapping with one entry deleted raises with a recognizable
message. Testing only the first would still pass even if someone deleted
the check from the model entirely, so both examples are needed together.
