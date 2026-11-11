---
mode: explanation
summary: "Explains the shared pattern of boot-time integrity checks that guard two derived stage-name mappings against silent drift, in LegislationPipelineRun and Pipeline::StageKeys."
status: agent-extracted
related: []
---
<!-- vale Vale.Spelling = NO -->

# Why the pipeline stage mappings check themselves at class-load time

Several places in the legislation pipeline keep two hand-written lists or
maps in step with each other — a stage-state list and its lookup table, or
a hyphenated-key map and its inverse. Each of those pairs runs a check as
its class loads, and raises immediately if the pair has drifted, rather
than waiting for the drift to misbehave quietly at runtime.

## LegislationPipelineRun::STAGE_STATUS_TO_DAG_NAME

`STAGE_STATUS_TO_DAG_NAME` is the single source of truth for mapping a
`*ing_*` status to its stage name. The orchestrator job's
`normalize_for_resume` uses it to map a stuck `fetching_law` status back to
the stage `fetch_law` so it can reset the matching `pipeline_run_stages`
row.

Keeping the mapping next to `PHASE_52_STAGE_STATES` — plus the class-load
check that every state has an entry — stops a future contributor from
adding an eighth stage state without a paired mapping, which would quietly
bring back the "stuck stage row never reset" bug. The check fails fast when
the class loads: every `PHASE_52_STAGE_STATES` symbol must have an entry in
`STAGE_STATUS_TO_DAG_NAME`, or the class raises. Adding a state without a
mapping now raises when the class loads, instead of silently breaking
`normalize_for_resume` later.

## Pipeline::StageKeys

`Pipeline::StageKeys` is the one place that maps the seven pipeline stages
between their hyphenated keys (`"fetch-law"`) and their Ruby symbols
(`:fetch_law`). Hyphenated strings are what travel between systems — URL
params, the `legislation_pipeline_runs.stages` database column, the
frontend's `StageKey` union type. Symbols are what Ruby uses inside the app
(`RunLegislationPipelineJob::DAG_ORDER`, state-machine event names). Every
place that converts between the two calls `.to_symbol` or `.to_key` here,
never a hand-written `.gsub("-", "_")`.

Two checks run as the class loads, the same way
`LegislationPipelineRun::STAGE_STATUS_TO_DAG_NAME` and
`RunLegislationPipelineJob::INLINE_DISPATCH_STAGES` do it:

1. **Round-trip check.** Does the map survive `KEY_TO_SYMBOL.invert`? If
   two keys ever folded onto one symbol, or the reverse, the inverted map
   would quietly lose an entry. This check catches that at load time.
2. **Orchestrator-order check.** Do `SYMBOL_TO_KEY`'s keys match
   `RunLegislationPipelineJob::DAG_ORDER`? Adding a stage symbol to
   `DAG_ORDER` without the matching `KEY_TO_SYMBOL` entry, or the reverse,
   would quietly break the orchestrator's `stages_to_run` translation.
   Failing as the class loads means CI sees it before a deploy does.

If the forward map, the inverted map, or the orchestrator's stage order
ever fall out of step, the class refuses to load, instead of misbehaving
quietly at runtime.
