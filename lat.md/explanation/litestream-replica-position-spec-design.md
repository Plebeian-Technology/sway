---
lat:
  mode: explanation
---

# Litestream::ReplicaPosition spec design

`Litestream::ReplicaPosition` is the only place in the replication-lag-check phase that reads data from outside Sway — it lists objects Litestream itself writes to GCS.

Every shape that listing can hand back (a pruned compaction level, an object name nobody expected, an empty bucket, a read that fails outright) has to land on exactly one of three outcomes, `:ok`, `:empty`, or `:unreadable` (see `Litestream::ReplicaReading::STATUSES`). A bug in the parsing logic above that three-way branch is deliberately left uncaught by `#call`'s own rescue, so it still escapes and turns the Sentry cron monitor red rather than being silently absorbed into the `:empty` or `:unreadable` reading — a bug inside this file has to keep looking like a bug inside this file, not like a report about the bucket.

## Shared stubbing convention

None of the specs touching this read path fake the underlying Google Cloud Storage client.

Each one stubs `#object_names` — the one private method that actually touches the network — on a real instance instead, so the rest of `#call` (parsing, the outcome branch, the `ReplicaReading` construction) runs for real. Three spec files share this pattern for the same read: `spec/services/litestream/replica_position_spec.rb`, `spec/services/database_backup_service_spec.rb` (its own listing call), and `spec/jobs/replication_lag_check_job_spec.rb` (this same reader one level up, through the job). Keeping the stub at that single seam means a change to how GCS is queried only has to be re-verified in one place per spec file, not reconciled against a fake client's behavior in each of the three.
