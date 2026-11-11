---
lat:
  mode: explanation
---

# Why the legislation pipeline lock holds for 4 hours

See also: [[docs/reference/legislation-pipeline-concurrency-layers.md|Legislation pipeline concurrency layers]] for the full three-layer locking design this lock (Layer 1) is part of, and [[docs/how-to/clear-stuck-legislation-pipeline-lock.md|Clear a stuck legislation pipeline lock]] for the operator recovery steps.

## What duration: actually controls

If a worker dies while holding the lock, the only thing that frees it is Solid Queue's semaphore reaper (`Dispatcher::ConcurrencyMaintenance#expire_semaphores`, a background `TimerTask` running `Semaphore.expired.delete_all`).

The lock is not reclaimed on the next acquire attempt — `Proxy#wait` returns false for a `value == 0` row whose `expires_at` has not passed yet.

`duration:` therefore controls two things at once:

- How long a stuck lock blocks new work after a worker is killed.
- How long the lock is guaranteed to hold while a run is still going.

Shortening it improves the first and worsens the second.

## Why 4 hours and not a shorter lock

A short duration such as 45 minutes would clear a lock left behind by a killed worker fast.

But a run longer than 45 minutes is ordinary. The `fetch_hearings` stage alone can spend over an hour on one bill (see `FetchHearingsService`'s `EXTRACTION_BUDGET_SECONDS` note), and it loops over every bill in the run.

When the lock expires mid-run, the only guard left is the controller's active-run check. That check fails when `sweep_stale_pipeline_runs` marks the run row terminal under a live worker. Two live runs then share the same attachment files on disk and the same `BillLlmProvisioning` rows. Layers 2 and 3 (see the concurrency layers reference above) stop database corruption, but the same paid LLM work runs twice.

A killed worker is rare; a slow run is routine. The trade therefore favours the honest run: it keeps its lock for up to 4 hours. After a crash, an operator either waits out the timer or clears the lock by hand. A spec pins the exact value so it changes only with a new decision, not by drift.
