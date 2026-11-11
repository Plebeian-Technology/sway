---
lat:
  mode: explanation
---

# Why ReplicationLagCheckJob is structured the way it is

`ReplicationLagCheckJob` checks that Litestream's continuous copy of the primary database is still moving. It runs every 15 minutes, production only (`config/recurring.yml`, `replication_lag_check`).

There's no Rails-environment guard in the class itself. The schedule file alone is what makes this production-only, which has a second benefit: it keeps `#perform` directly callable from a spec without an environment check getting in the way.

## Reader, decision, sender

The job reads a replica position, asks `Litestream::ReplicationLagCheck` what that position means against the heartbeat's last known state, and writes the resulting decision onto the single `ReplicationHeartbeat` row.

The job reads a replica position, asks `Litestream::ReplicationLagCheck` what that position means against the heartbeat's last known state, and writes the resulting decision onto the single `ReplicationHeartbeat` row — an earlier plan wrote only the number and the time; this job writes every column the decision produces. The reader reports, the decision decides, and this job sends. Nothing else in this check talks to Sentry.

## Why there's no broad rescue

This class deliberately has no broad `rescue` anywhere.

An unexpected error must escape and turn the Sentry cron monitor (`sentry_monitor_check_ins`) red, because a watchdog that reads green while it's actually broken is the failure this job exists to end: a silent watchdog that has stopped checking.

The individual design decisions inside `#perform` and its private methods used to live in place as short comments citing their own design decision. A comment that argues a reason moves into documentation regardless of size, so each is collected below, in the order it appears in the file.

## The monitor slug is set by hand

Left unset, sentry-ruby derives `MONITOR_SLUG` from the class name, so renaming this job later would silently create a second monitor in Sentry and orphan the first one's history and alert rules.

## The crontab constant must match config/recurring.yml exactly

`MONITOR_CRONTAB` must equal, character for character, the schedule under `replication_lag_check` in the production block of `config/recurring.yml`.

Nothing in the library checks that for you, and a mismatch would make the monitor expect runs at times they never happen.

## The check-in margin is minutes, not slots or runs

`MONITOR_CHECKIN_MARGIN_MINUTES` is minutes, not slots or runs — the gem's own doc comment on `MonitorConfig#checkin_margin` says so.

Last good check-in at T-15, next expected at T, marked missed at T+30: 45 minutes after the last completed run. That is its own bound, separate from the stall alarm, the read-failure alarm and the empty-listing alarm, which alert 30 minutes after the last good run (`Litestream::ReplicationLagCheck::FORGIVENESS_THRESHOLD`).

## Why there is no retry_on

`Sentry::Cron::MonitorCheckIns::Patch` is prepended around `#perform`, which puts the check-in wrapper INSIDE ActiveJob's retry handling.

A transient crash sends the `:error` check-in and re-raises before any retry is ever scheduled, so a `retry_on` declaration would not protect the monitor. `checkin_margin` does not help either — it covers a check-in that never arrived, not one that arrived reporting failure.

## Every alarm string is a frozen constant with no interpolated value

Sentry groups message events by their text, so a changing value in the text would mint a new issue every run and destroy the rising alarm count the job depends on.

Everything that changes rides in the structured `extra:` field instead. `# frozen_string_literal: true` at the top of the file already freezes every string literal.

## write_heartbeat uses update_columns, never update! or save

Both `update!` and `save` skip the SQL entirely when every attribute already matches the database (activerecord-8.1.3.1 persistence.rb:931-940).

Both `update!` and `save` skip the SQL entirely when every attribute already matches the database (activerecord-8.1.3.1 persistence.rb:931-940), and a heartbeat that wrote nothing would make the NEXT run report a stall against its own missing write, every 15 minutes, forever. `update_columns` has no dirty check, so a run always issues an UPDATE — that is the property this method depends on, not a property of the values it happens to write. It also skips validations, callbacks and the automatic timestamp, which is why `updated_at` is set by hand.

## The three alarms route to three different machines

A stall alarm points at the copier, a read-failure alarm points at Sway's own Google credentials for an unreadable bucket, and an empty-listing alarm points at the deploy config.

Collapsing any two would send somebody to the wrong machine. `:first_run` and `:healthy` send nothing.

## The recovery message's duration lives in extra:, not the text

One decision wants the message to say how long the copy was stopped; another forbids a changing value in the text.

The duration rides in `extra:` and the text says it is on the event. `previous_stalled_since` is read in `#perform` before `write_heartbeat` overwrites the row — `decision.stalled_since` is already nil by the time `report_recovery` runs, because `:recovered` is the outcome that clears it.

## The read-failure alarm captures an exception, not a message

The real Google error keeps its class, its code and its cause, which separates a missing key from a network blip.

`READ_FAILURE_ALARM` rides in `extra:` rather than being the captured message, so the runbook's exact words are still searchable against this event. A fixed fingerprint keeps every read failure in one Sentry issue, the same grouping the message-based alarms get for free from their unchanging text.

## What the read-failure and empty-listing examples cover

An empty object listing is its own third alarm, never conflated with a stall, naming the bucket and path the reader actually used.

An empty object listing is its own third alarm, never conflated with a stall, naming the bucket and path the reader actually used — distinct from both the stall alarm (a copier problem) and the read-failure alarm (a credentials/network problem). The three stall counters on the heartbeat move independently of one another, proven by a stall/read-failure/stall walk through the job.

## Why the cron-monitor examples drive the job with perform_now, not .new.perform

`Sentry::Cron::MonitorCheckIns::Patch` is prepended around `#perform`, so only `perform_now` is guaranteed to walk the job through that wrapper end to end.

`Sentry::Cron::MonitorCheckIns::Patch` is prepended around `#perform`, so only `perform_now` is guaranteed to walk the job through that wrapper end to end — unlike the examples elsewhere in this file, which call `described_class.new.perform` directly and never touch the check-in patch. Nothing inside a stopped Rails process can report the stop, which is the whole reason this job checks in to a Sentry cron monitor at all: the guarantee (an unexpected error must escape `#perform`, and the check-in that goes out must report it) is what makes the monitor's green mean the check itself is working.

## Why required_error exists

`Litestream::ReplicaPosition` always sets `error:` when status is `:unreadable`, but `Litestream::ReplicaReading#error` is typed `Exception?`.

`Litestream::ReplicaPosition` always sets `error:` when status is `:unreadable`, but `Litestream::ReplicaReading#error` is typed `Exception?` — nothing connects that guarantee to the type system, so this is the boundary guard, matching `Litestream::ReplicationLagCheck#required_position`.

## ReplicationHeartbeat holds exactly one row

`ReplicationHeartbeat` is a singleton table: exactly one row, ever, at primary key 1.

One row means one meaning — the stored position and the three stall counters describe a single check, not an accidental fleet of them. `ReplicationLagCheckJob` is the only writer.

`#enforce_single_row` is a model validation that duplicates a database check constraint (`id = 1`) already in the migration. The validation exists anyway because it gives the same refusal a message a person can act on, before the database is ever asked.

`ReplicationHeartbeat.singleton` returns the one row, creating it at id 1 if missing. The migration seeds this row the first time migrations run, but `db/schema.rb` carries no data — the test database is built by loading that file, so the seeded row from the migration does not exist there. `.singleton` is what a run against a fresh test database falls back to.

## Why the spec stubs only Litestream::ReplicaPosition.object_names

`spec/jobs/replication_lag_check_job_spec.rb` stubs `Litestream::ReplicaPosition` at exactly one seam — `#object_names`, the one call that touches the network — on a real instance.

Everything downstream of that call (parsing the segment listing, deciding what to store via `Litestream::ReplicationLagCheck`, writing the heartbeat row) runs for real. That is what proves the one path this check wires end to end — a listing of Litestream segment names in, the highest number out, written onto the single heartbeat row every run, even when nothing moved — rather than a spec that only proves a mock of it.

`Litestream::ReplicaPosition.new` is stubbed to always hand back the same instance, the way `spec/jobs/backup_database_job_spec.rb` stubs `DatabaseBackupService.new` — the job builds a fresh reader on every call to `#perform`, so the stub has to survive more than one call within an example.

## What the stall-alarm and recovery-message examples cover

The "stall alarm and the recovery message" examples exercise the alarm rule (the first stall is forgiven.

The "stall alarm and the recovery message" examples exercise the alarm rule (the first stall is forgiven, the second alarms, and every stalled run after that alarms again with the same constant text so Sentry folds them into one issue) and the recovery rule (the flip back to healthy sends one info-level message naming the outage length). They watch `Sentry` — stubbing `Sentry.capture_message`/`Sentry.capture_exception` on the real constant — rather than replacing it with a double, following the same template as `spec/lib/sqlite_integrity_check_spec.rb`: `spec/support/report_application_errors.rb` already captures the real `Sentry` constant before any example runs, so swapping it out from under that harness would break the harness rather than isolate the example.
