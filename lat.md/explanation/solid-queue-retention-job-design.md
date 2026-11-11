---
lat:
  mode: explanation
---

# Why SolidQueueRetentionJob is shaped the way it is

`SolidQueueRetentionJob` is a weekly cleanup sweep for the Solid Queue database.

Solid Queue keeps finished jobs (`preserve_finished_jobs = true`) and ships no auto-clear, so completed/discarded rows pile up forever. Dead failures pile up separately — a job that runs out of retries lands in `solid_queue_failed_executions` with `finished_at` NULL, which the finished-jobs sweep never touches. This job deletes both kinds, keeping failures longer since they're the rows worth inspecting.

It is registered in `recurring.yml` with `schedule:`, NOT `cron:` — solid_ queue 1.4.0 only registers tasks that carry a `:schedule` key. It works on the queue database, where multi-db routing sends `SolidQueue::Job` / `::FailedExecution`.

## Why the retention windows differ

Finished jobs are kept ~1 week so a failed deploy / flaky run stays inspectable (`FINISHED_RETENTION_DAYS`). Permanently-failed jobs are kept longer — they are the rows most useful for debugging (`FAILED_RETENTION_DAYS`).

## Why deletes are batched

Deletes happen in batches (`BATCH_SIZE`) so a large first run can't hold the queue database's write lock in one giant DELETE (matches the default batch size of `SolidQueue::Job.clear_finished_in_batches`).

## Why clear_finished uses plain ActiveRecord instead of the gem's batching method

Plain ActiveRecord is used instead of the gem's `clear_finished_in_batches`, so the test model that stands in for the multi-db setup (and lacks the gem's `Clearable` concern) can run it too.

Selecting ids first and then deleting by id is always safe on SQLite and caps each DELETE at `BATCH_SIZE` rows.

## Why prune_failed deletes the child row explicitly

`#prune_failed` deletes permanently-failed jobs by the age of their `FailedExecution` row.

The job -> `failed_execution` link is a database foreign key, not a Rails `dependent: :destroy`, so the child rows are deleted explicitly inside the transaction (correct even if SQLite foreign-key enforcement is off). The `finished_at: nil` guard keeps this set separate from `#clear_finished`. There is no race: a job that is mid-retry has already deleted its `FailedExecution` row, and a permanently-failed job sits in no ready/claimed/scheduled table.
