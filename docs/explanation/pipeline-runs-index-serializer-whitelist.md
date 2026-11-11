---
mode: explanation
summary: "Why /pipeline_runs' index rows go through a whitelisting serializer instead of .map(&:attributes), and why remote_run_id is a deliberate exception on the allow list."
status: agent-extracted
related: [docs/explanation/pipeline-runs-index-only-surface.md]
---

<!-- vale Vale.Spelling = NO -->

# Why `/pipeline_runs`' rows go through a whitelisting serializer

The old `.map(&:attributes)` dump on the pipeline runs index handed over
every database column, including `error_message`, `parent_run_id`, and
the whole `cached_full_breakdown` blob — none of which the admin index
page needs, and some of which is internal bookkeeping that should never
reach the browser. The index now goes through a serializer that only
returns an allow-listed set of fields.

`remote_run_id` IS included, on purpose, despite looking like the same
kind of internal id the whitelist otherwise excludes: it names the
WebSocket stream in `PipelineRunChannel` — a random uuid with nothing
personal in it, on an admin-only page — which the index page subscribes
to so the list updates itself. It earns its place on the allow list; the
genuinely internal columns stay off it.
