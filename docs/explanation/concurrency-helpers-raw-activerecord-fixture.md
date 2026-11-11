---
mode: explanation
summary: "Why ConcurrencyHelpers#seed_active_pipeline_run writes its fixture row straight through ActiveRecord instead of a FactoryBot factory."
status: agent-extracted
related: []
---

# Why `seed_active_pipeline_run` bypasses FactoryBot

`ConcurrencyHelpers#seed_active_pipeline_run` creates and saves a
`LegislationPipelineRun` that is still going (not yet finished), so
concurrency specs have a run in progress to work against. It writes the
row straight through `LegislationPipelineRun.create!` rather than a
FactoryBot factory, so a later change to that factory's own defaults (a
new required attribute, a changed default status) cannot silently break
what this specific in-progress-run fixture needs to stay true — the run
must exist with `status:` `"queued"` or `"running"` and no `finished_at`,
regardless of whatever the factory considers a normal default row.
