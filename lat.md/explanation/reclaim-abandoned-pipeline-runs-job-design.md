---
lat:
  mode: explanation
---

# Why ReclaimAbandonedPipelineRunsJob exists

It closes a pipeline run whose worker stopped first; one such row switches the Run button off for everybody. It cannot cover the jobs container being down, because it lives in it.

## Why close re-checks abandoned? under the lock

`with_lock` reloads, so `#abandoned?` is re-asked about committed state: a run that woke up since the query in `#perform` keeps going.

## Why close also checks can_force_fail?

This is a belt on a row that moved under us, not a second path: `force_fail` already reaches every status `#abandoned_candidates` selects.

## Why the error message is set, not saved, before force_fail!

Set, not saved: the transition's own UPDATE carries it, so no reader ever sees a failed run with no reason on it.

## Why the run is marked failed, not cancelled

Failed, not cancelled — nobody decided anything, and failed is the status the Resume control reads.

## Why abandonment_message dashes the stage name

The stage name is converted from underscored (`fetch_law`) to dashed (`fetch-law`), matching the stage names shown on the Run pipeline control, not the underscored ones the status column and stage rows carry.

## Why abandonment_message exists as its own method

It answers the question the screen raises: why does a run that was working now say failed.

The message is built for the operator reading the failed status on the Run pipeline control, not for logs — hence the full sentence wording instead of a terse status string.

## Why per-stage status is ever written directly, bypassing the state machine

A worker killed inside a stage leaves the run's per-stage status in a shape no state-machine event can leave: every event out of a per-stage state means "this stage finished", and none of them did when the worker died.

So `#force_fail!`/the reclaim path writes the status directly — the one place in `LegislationPipelineRun` that does — and does by hand the two things the machine would otherwise have done for it.

## Why abandoned? lives on the model, not duplicated at each reader

`LegislationPipelineRun#abandoned?` answers whether anybody is still working on a run.

The judgement lives on the model, and both readers — this job's sweep and the two screens that read it through `#to_builder` — share that one definition rather than each deciding independently.

## The frontend abandoned field

Whether any worker is still carrying this run. Only the server can tell — the proof is in the queue database. Optional because channel deltas leave it out, and absent must read as attended.
