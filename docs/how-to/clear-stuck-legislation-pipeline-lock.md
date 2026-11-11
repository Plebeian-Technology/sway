---
mode: how-to
summary: "Gives the Rails console steps to manually clear a stuck legislation pipeline concurrency lock left behind by a dead worker."
status: agent-extracted
related: []
---
# Clear a stuck legislation pipeline lock

<!-- vale Vale.Spelling = NO -->

Use this when a `RunLegislationPipelineJob` worker died and left the Solid
Queue concurrency lock held, blocking new pipeline runs before the semaphore
reaper clears it on its own. Background on the lock and why it holds for 4
hours: [Why the legislation pipeline lock holds for 4 hours](../explanation/legislation-pipeline-lock-duration.md).

## Steps

1. Open a Rails console:

   ```
   dip run rails c
   ```

2. Delete the semaphore row for the pipeline lock:

   ```ruby
   SolidQueue::Semaphore.find_by(key: "legislation_pipeline_global")&.delete
   ```

The next enqueue can now acquire the lock.
