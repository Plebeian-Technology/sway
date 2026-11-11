---
mode: explanation
summary: "Why legislation_pipeline_run and active_legislation_pipeline_run diverge when a ?run_id= pin names a finished run while a different run is still active."
status: agent-extracted
related: [docs/explanation/pipeline-run-id-cross-tab-coordination.md]
---
<!-- vale Vale.Spelling = NO -->

# Why the pinned run and the active run are two different props

`?run_id=` is carried onto every Bill Creator tab so a run
picked on the Pipeline tab survives a tab change
(`withCarriedRunPin.ts`). `LegislationPipelineRunSourcing`'s
`inertia_share` runs on every `BillsController` action, so that pin rides
along to tabs that never meant to ask for it.

`legislation_pipeline_run` always prefers the pin. That is right for the
Pipeline tab's own display — an operator who pinned a specific run wants to
see that run, not whatever else is running. It is wrong for anything that
answers "is a run blocking new work right now": `RunConflictBanner` and the
Summary tab's ActionCable subscription both need to know about a
genuinely `running` run even when a pin names a different, finished one.

The combination that exposes the gap — a `running` run and a pin naming a
different, `succeeded` run at the same time — is exactly what production
produces the moment an operator pins an old run and leaves the Pipeline
tab. `active_legislation_pipeline_run` exists to answer that question
correctly: it names the running run regardless of the pin, while
`legislation_pipeline_run` keeps naming the pin.
