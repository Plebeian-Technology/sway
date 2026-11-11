---
lat:
  mode: explanation
---

# Litestream replication-lag internals

This covers the two classes `ReplicationLagCheckJob` reads from and hands its decision to.

This covers the two classes `ReplicationLagCheckJob` reads from and hands its decision to: `Litestream::ReplicationLagCheck`, which turns one reading and the heartbeat's last known state into a decision, and `Litestream::ReplicaPosition`, which produces that reading in the first place. Both belong to the replication-lag-check phase; see [[docs/explanation/replication-lag-check-job-design.md|replication-lag-check-job-design.md]] for the job that ties them together.

## ReplicationLagCheck reads nothing outside itself

`ReplicationLagCheck` reads no clock (the caller passes `now`), no database, no environment and no network. That is what lets its whole case matrix be walked as a table, with no setup beyond the keyword arguments the class takes.

Each of the three counters — `consecutive_stalls`, `consecutive_read_failures` and `consecutive_empty_listings` — is touched only by its own condition. A change of condition never resets ANOTHER condition's counter: a shared counter would let stall / read-failure / stall land back at one and never reach two, the hole that independent counters close. Only a successful non-empty listing resets the other two, because only that proves both that reading works and that the path is right.

## Why FORGIVENESS_THRESHOLD is the same number for all three conditions

The same threshold applies to all three conditions on purpose, so all three fault alarms share one bound.

The same threshold applies to all three conditions on purpose, so all three fault alarms share one bound: 15 minutes (`config/recurring.yml`) times the one forgiven run plus the alarming run is 30 minutes from the last good run to the alert. The cron monitor's missed check-in margin is a separate 45-minute bound — see `ReplicationLagCheckJob::MONITOR_CHECKIN_MARGIN_MINUTES`.

## call's else branch is unreachable, on purpose

The RBS status type is a `(:ok | :empty | :unreadable)` union, so Steep proves the `else` branch dead and types `status` there as `bot`, which cannot answer `#inspect`.

The RBS status type is a `(:ok | :empty | :unreadable)` union, so Steep proves the `else` branch dead and types `status` there as `bot`, which cannot answer `#inspect` — so the message stays a fixed string rather than echoing the value. This is the runtime guard for a dynamic caller that bypasses Steep, the same reason `ReplicaReading#initialize` raises on an unrecognized status.

## required_position

Steep already enforces that `position.

Steep already enforces that `position: Integer?` and `status: :ok` never travel together without a real number at the call site (the job that builds this object always reads position off `Litestream::ReplicaReading` when its status is `:ok`). `#required_position` is the runtime guard for a dynamic caller that bypasses Steep. It is declared to return `Integer` (not `Integer?`) in the RBS, and the trailing `#: Integer` annotation states that at this one expression, rather than relying on flow-sensitive narrowing after the raise above — Steep does not narrow a local across a modifier-if `raise`, only across `return`.

## ok_decision: the first run, a stall, or progress

`#ok_decision` covers the first run, a number that moved forward (healthy or recovered), or a number that did not (a stall).

Equal counts as no progress too: the stored number never goes down, and standing still is exactly what a stall is.

`consecutive_stalls >= 1` means the run before this one was stalled — that is the flip the recovery message is sent for, and it fires whether one stall was forgiven or several already alarmed.

## Why stalled_since is measured from a timestamp, not the stall count

`#recovered_outage_seconds` is measured from the stalled-since time that was passed in, never from the stall count.

`#recovered_outage_seconds` is measured from the stalled-since time that was passed in, never from the stall count — the count freezes during read failures, so multiplying it by the interval would understate the exposure window, and that window is exactly what tells someone how much data a dead disk would have cost.

A stall count of one or more with no stalled-since time should not occur in production, but this reports the seconds as absent rather than raising a nil-arithmetic error out of a check whose whole purpose is to notice trouble quietly.

`#stall_decision` sets `stalled_since` on the run the count first leaves zero, and leaves it unchanged on every stalled run after that, so the recovery message measures from the real start of the outage rather than resetting on each alarm.

## Why a read failure freezes the stall count instead of resetting or incrementing it

A read failure tells you nothing about whether the copy moved, so `#read_failure_decision` leaves the stall count, the stored number and the stalled-since time exactly as they arrived.

Resetting the stall count would open a hole where a genuine outage alongside flaky reads alternates and never reaches two consecutive stalls; incrementing it would eventually fire the stall alarm and send someone to the copier when the fault is on Sway's side reading the bucket, not on Litestream's side writing to it.

## Why an empty listing is not a stall

An empty listing is not a stall.

An empty listing is not a stall: a mistyped `SWAY_LITESTREAM_PATH` would otherwise alarm as a broken copier forever and send someone to reboot a healthy machine, and this check is the first time that path value reaches the app container at all.

## ReplicaPosition: reading the replica's position without downloading it

`Litestream::ReplicaPosition` reads how far Litestream's continuous copy of the primary database has gotten.

`Litestream::ReplicaPosition` reads how far Litestream's continuous copy of the primary database has gotten, by listing the object names Litestream itself writes under `SWAY_LITESTREAM_PATH` and finding the highest segment number among them. It downloads nothing.

Litestream 0.5's LTX layout, confirmed against the pinned 0.5.15 binary, is `<path>/ltx/<level>/<min>-<max>.ltx` — one folder per compaction level, min/max zero-padded hex transaction IDs (`docs/litestream-restore.md`'s `-txid` flag restores to "a specific hex transaction ID"). Retention prunes level 0 over time, so a segment can only be missing from level 0 — never absent from every level at once while the replica is healthy. `#call` therefore scans every level and keeps the highest max found anywhere, not just the one in the lowest-numbered folder.

### Why SEGMENT_NAME_PATTERN is anchored on the tail

`SEGMENT_NAME_PATTERN` is anchored on the tail rather than the whole string: the prefix already passed to `files(prefix:)` limits what GCS returns, so this only has to reject a name shaped unlike a segment.

The two hex numbers are matched at any length, case-insensitive — Litestream lowercases them, but nothing here depends on that holding forever. A width hard-coded to one level's padding would silently drop a differently-padded name from another level and answer with the wrong number.

### Why a bug in call's own parsing is left uncaught

`#call` lists names, parses the highest segment number out of them, and reports what it actually found.

It never raises on a read failure — that becomes the `:unreadable` reading — but a bug in the parsing below is deliberately NOT caught here, so it still escapes and turns the monitor red rather than silently reading as "empty".

### Why path and bucket_name are read per call, not class-body constants

`#path` and `#bucket_name` are read per call: `SwayDeployConfig.fetch` raises on a blank value, which would make this class unloadable everywhere the value is absent.

The neighbouring `DatabaseBackupService` does the opposite (a class-body `BUCKET_NAME` constant) because `config/initializers/deploy_values.rb` already checks its value at boot — this class's own value joins that same boot check instead of repeating the constant pattern.

### Why object_names has no rescue of its own

`#object_names` is copied from `DatabaseBackupService#existing_backups` WITHOUT its rescue.

That rescue swallows the error into an empty array, which would make "could not list" read exactly like "listed fine, found nothing" — the one distinction this whole check exists to keep.

### Why parse_position returns nil instead of raising

`nil` means the name did not match the expected shape, and `filter_map` drops it rather than raising — a stray object under the same prefix must not stop the run.
