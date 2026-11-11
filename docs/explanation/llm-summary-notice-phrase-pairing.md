---
mode: explanation
summary: "Explains why two frontend notice components hand-copy SummaryRunRelease's release-message phrases, the contradiction that resulted, and how the pairing is pinned from both sides."
status: agent-extracted
related: [docs/explanation/summary-run-release-message-history.md, docs/reference/summary-run-release-message-invariants.md]
---
<!-- vale Vale.Spelling = NO -->

# Why the in-flight notices hand-copy SummaryRunRelease's phrasing

`LlmSummaryInFlightNotice` and `LlmSummaryAbandonedRunNotice` are the two
frontend components a still-stuck row can reach before
`ReclaimAbandonedSummaryRunsJob` ever touches it. Both branch on
`generation_status` and print copy that has to agree with the verb phrases
`SummaryRunRelease::RELEASED_UNSTARTED_ERROR` ("never started") and
`RELEASED_IN_FLIGHT_ERROR` ("stopped part-way") use once the sweep actually
releases the row.

## The contradiction

Before the fix, both notices printed "stopped without finishing" for every
status they drew, `pending` included. The sweep then released that same
`pending` row with `RELEASED_UNSTARTED_ERROR`, whose text says "never
started." One operator, looking at one row, could read two directly opposed
statements about it within fifteen minutes of each other — one from the
notice while the row was still stuck, the other from the release message
after the sweep freed it.

## Why the copy has to be hand-maintained

Nothing in TypeScript can read a Ruby constant, so the two notice
components' copy is a hand-typed mirror of the two Ruby phrases, not a
shared reference to them. A hand-mirror goes stale in silence the moment
either side changes wording and nobody updates the other.

## How the pairing is pinned from both sides

The backend half is pinned by a spec that fails if either constant drops
its phrase, in `spec/jobs/reclaim_abandoned_summary_runs_job_spec.rb`. The
frontend half is pinned separately, in
`app/frontend/components/admin/creator/llm-summary/__tests__/BillCreatorLlmSummaryStatus.test.tsx`.
Each side can only catch a reword on its own side; keeping both wired is
what keeps a future rename from reopening the contradiction it closed.

## LlmSummaryAbandonedRunNotice field notes

`generationStatus` (`bill_llm_provisioning.generation_status`) picks which
of two messages is shown; the split mirrors the server's own.

`hasTestimony` (`bill_llm_provisioning.has_testimony`) is the same
predicate `GenerateBillSummaryJob` gates the positions call on, not a
guess about what a run will do.

THE COST IS AN UPPER BOUND: the browser can only see one gate
(`has_testimony`), while the two paid calls are gated separately — "no
more than" is the only claim true in every case.

WHAT WENT WRONG differs by status: `SummaryRunRelease` calls `pending`
"never started" and `generating` "stopped part-way" — only `generating`
may have actually run.
