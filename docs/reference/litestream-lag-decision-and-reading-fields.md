---
mode: reference
summary: "Catalogs the fields on Litestream::ReplicaReading and Litestream::LagDecision, the two Data.define value objects the replication-lag-check phase passes between its reader, its decision class, and the job."
status: agent-extracted
related: [../explanation/replication-lag-check-internals-design.md, ../explanation/replication-lag-check-job-design.md]
---
<!-- vale Vale.Spelling = NO -->

# Litestream::ReplicaReading and Litestream::LagDecision fields

Both belong to the replication-lag-check phase. See
[replication-lag-check-internals-design.md](../explanation/replication-lag-check-internals-design.md)
for why each field exists.

## Litestream::ReplicaReading

One read of the Litestream replica's position, built by
`Litestream::ReplicaPosition` and consumed by `ReplicationLagCheckJob`.

`status` is one of three symbols, and the three never collapse into each
other — that separation is the whole point of this phase:

| `status` | Meaning |
|---|---|
| `:ok` | The listing succeeded and named at least one segment. `position` holds the highest segment number found. |
| `:empty` | The listing succeeded and named nothing at all. Not a stall: an empty listing means the path or bucket is wrong, which is a different alarm from a copy that has stopped. |
| `:unreadable` | The listing itself raised. `error` holds what it raised. |

`bucket_name` and `path` are the values the reader actually used, not the
ones anybody expected — an alarm built from this reading names what
Sway actually asked GCS for.

## Litestream::LagDecision

What `Litestream::ReplicationLagCheck` decided from one reading and the
heartbeat's last known state. `ReplicationLagCheckJob` reads
this to decide what to write onto `ReplicationHeartbeat` and which of the
four Sentry calls, if any, to make.

| Field | Holds |
|---|---|
| `outcome` | One of six symbols, naming what just happened: `:first_run` (no previous number existed to compare against), `:healthy` (the number moved forward and nothing was stalled), `:recovered` (the number moved forward and the run before this one was stalled — fires exactly once per outage), `:stall` (the number did not move forward), `:read_failure` (the listing itself raised), `:empty_listing` (the listing succeeded and named nothing at all). |
| `alarm` | Whether the outcome's own counter has reached `ReplicationLagCheck::FORGIVENESS_THRESHOLD`. Only `:stall`, `:read_failure` and `:empty_listing` ever set this true. |
| `last_replica_txid` | The number to store on the heartbeat row. |
| `consecutive_stalls`, `consecutive_read_failures`, `consecutive_empty_listings` | The three counters to store, each touched only by its own condition. |
| `stalled_since` | The time to store, or nil. Set the run the stall count first leaves zero, cleared on `:recovered`. |
| `stalled_for_seconds` | How long the copy was stopped, present only on `:recovered`, measured from `stalled_since` rather than derived from the stall count (which freezes during read failures and would understate the window). |
