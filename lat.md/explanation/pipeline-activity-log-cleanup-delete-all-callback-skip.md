---
lat:
  mode: explanation
---

# Proving delete_all skips before_destroy on PipelineActivityLogEntry

`PipelineActivityLogCleanupJob` clears out old entries with `delete_all`, which is fast because it sends one SQL DELETE and never loads the rows.

The price: any `before_destroy` callback is skipped, and `dependent: :destroy` associations are never followed. The spec shows the problem directly rather than only asserting the rule: it adds a temporary `before_destroy` that bumps a counter, runs the cleanup job's `delete_all`, and watches the counter stay at zero — the delete happens down in SQL, below where callbacks live.

## Why there is no positive control

There is no matching positive control proving the counter *would* have incremented under a normal `.destroy`.

Saved entries are read-only (`readonly?` is true once persisted), so `.destroy` cannot be called on one to watch the callback fire. The negative result — the counter stays zero — is the one that matters here.

## Why teardown uses skip_callback, not reset_callbacks

Cleanup calls `skip_callback(:destroy, :before, callback_proc)` with the same block that was added, so only this test's callback is removed.

Calling `reset_callbacks(:destroy)` instead would wipe the whole destroy chain on the class for the rest of the process — Rails' own `:destroy_associations` callback included, if a `dependent: :destroy` is ever added. That's harmless today, but becomes a trap once specs run in random order.

## Why the job's retention rule excludes rows by both subject_type and subject_id

`PipelineActivityLogCleanupJob` deletes every aged row EXCEPT those tied to a run being kept.

The `NOT` clause has to match on BOTH `subject_type` AND `subject_id`. A plain `NOT IN` on the id alone would also spare rows whose subject is not a run at all, and those are meant to be deleted.

## Why PipelineActivityLogEntry must never gain a destroy callback

CONTRACT: `delete_all` here is intentional.

It fires one SQL DELETE and skips Rails callbacks, which keeps this daily sweep fast. Keeping the 50 newest runs across ~30 days of roughly 1000 entries per run can easily leave more than 100k rows to delete on a busy install. So `PipelineActivityLogEntry` MUST NOT gain a `before_destroy` callback or a `dependent: :destroy` association. If someone adds one, change the job to a batched `find_in_batches { |b| b.each(&:destroy) }` so the callback actually runs. The model spec checks that no `:destroy` association exists.

## The create! side effect to watch for

`create!` fires the `after_commit` `dispatch_pipeline_activity_transport` callback.

In model specs the websocket side does nothing, because no consumer is connected. If that callback ever gains a real side effect (forwarding to a security log, say), this test would set off two unwanted sends per run — switch to `.insert!` then, as long as the `before_destroy` check still holds without ActiveRecord's create callbacks.
