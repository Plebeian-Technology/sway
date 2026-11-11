---
mode: explanation
summary: "Explains why RunLegislationPipelineJob deliberately declares no retry_on for network errors, since none can reach ActiveJob's retry machinery."
status: agent-extracted
related: []
---

<!-- vale Vale.Spelling = NO -->

# Why RunLegislationPipelineJob has no retry_on for network errors

`RunLegislationPipelineJob` declares no `retry_on` for network errors, and
its absence is deliberate.

There used to be one, for `Faraday::TimeoutError` and
`Faraday::ConnectionFailed`. No Faraday error can reach ActiveJob's retry
machinery from here: every network call happens inside a stage, and both
stage runners rewrap what escapes them as `StageError` — the run-level one
names Faraday explicitly, the per-bill one catches everything. Nothing on
the remaining paths through `#perform` touches the network.

It was not merely dead. Had it ever fired, it would have re-run a job whose
run row `#handle_run_failure` has already marked failed. Retrying a stage is
the stage's own business — see `FaradayStack`'s per-request retries and the
per-bill failure budget (`CONSECUTIVE_FAILURE_BUDGET`) — and the
`retry_on` declaration said otherwise while doing nothing.
