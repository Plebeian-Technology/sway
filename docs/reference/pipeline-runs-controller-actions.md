---
mode: reference
summary: "Catalogs the three admin actions on PipelineRunsController and what each one does."
status: agent-extracted
related: ["docs/reference/legislation-pipeline-run-orphan-detection.md", "docs/explanation/pipeline-runs-index-only-surface.md"]
---

<!-- vale Vale.Spelling = NO -->

# PipelineRunsController actions

Admin-only screen for managing legislation pipeline runs. A separate `#show`
page for a single run was removed, and so was the single-row
orphan delete; these three actions remain.

| Action | Method/route | What it does |
|---|---|---|
| `#index` | `GET /pipeline_runs` | Read-only landing page listing recent runs. |
| `#force_fail` | `POST /pipeline_runs/:id/force_fail` | Moves an in-flight run to `:failed` via the state-machine event; requires the operator to type `"force fail"` into `confirm_phrase` so a forged or accidental request can't trigger it. |
| `#destroy_orphans` | `DELETE /pipeline_runs/orphans` | Deletes every stuck run for which ALL THREE hold: no Solid Queue job for it, `created_at` older than 4 hours, and status in `{queued, running}`. See [orphan detection](../reference/legislation-pipeline-run-orphan-detection.md) for the shared checks behind this. |

Every admin-gated controller in this codebase carries
`before_action :verify_is_sway_admin` and is listed in the
`lib/tasks/sway_lint.rake` allowlist — see `CLAUDE.md`.
