---
mode: explanation
summary: "Explains why last_failed_pipeline_run_summary carries a run id and how that id ties into the Pipeline tab's run selection."
status: agent-extracted
related: []
---

# Why the last-failed-run summary carries a run id

`last_failed_pipeline_run_summary` returns the most recent FAILED
`LegislationPipelineRun` for a bill, or nil, as a small hash: `run_id`,
`error_message`, `failed_at`. It stays small on purpose, since it is built
on every render of the Summary tab's alert.

## Why the run id matters

The Pipeline tab's Resume/Restart buttons act on whichever run
`LegislationPipelineRunSourcing` currently picks: the run named by
`?run_id=`, else the newest in-flight run, else the newest run of any
status. That selection has no built-in reference to the bill the Summary
tab is showing.

The Pipeline tab's own run-selector dropdown cannot fill that gap either,
because it is capped at `RECENT_PIPELINE_RUNS_LIMIT` — a run that has
scrolled off the dropdown is still a real run an operator may need to see.

`#explicitly_selected_pipeline_run`'s uncapped `find_by(id:)` lookup is what
makes a link carrying this run id reliable: the Summary tab's alert can link
straight to the failed run's Pipeline tab view, regardless of how far back
in the run history it sits.

## The frontend's `IBillPipelineLastFailure.run_id`

The failed run's own id. The alert links to the Pipeline tab with
`?run_id=` set to it, because that tab draws Resume and Restart for the run
it is showing and picks that run without looking at this bill.
