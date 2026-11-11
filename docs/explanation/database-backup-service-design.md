---
mode: explanation
summary: "Explains DatabaseBackupService's online-backup approach, its size-regression refusal guard, and why it prunes only after a successful upload."
status: agent-extracted
related: []
---
<!-- vale Vale.Spelling = NO -->

# Why DatabaseBackupService is built the way it is

`DatabaseBackupService` copies one SQLite database to Google Cloud Storage
(GCS) and deletes copies older than the retention window. This is a
stopgap until full Litestream streaming backups arrive. Two callers share it:
`SwayTask#backup_db` at boot, and the scheduled `BackupDatabaseJob`
(`config/recurring.yml`).

It uses SQLite's online backup API (`SQLite3::Backup`), which produces a
consistent copy even while the database is in WAL mode (SQLite's
write-ahead log) and taking writes. A raw file copy could capture a
half-written database, so the service never does that. The copy reads
through a separate read-only connection, so the live database is never
touched.

`#call` returns one of three symbols:

- `:skipped` — the source DB file does not exist (e.g. volume still mounting)
- `:refused` — the backup looked like a freshly seeded database; NOTHING was
  uploaded and NOTHING was pruned
- `:ok` — backup uploaded and old backups pruned

## Why BUCKET_NAME is not written down here

The bucket the copies go to names one person's cloud account and this
repo is public. A WRONG value is the dangerous kind: every upload would
report success into a bucket nobody reads, and the loss would only be
found during a restore. So nothing is guessed, and
`config/initializers/deploy_values.rb` checks it while production starts
rather than waiting for the first backup.

## Why pruning only happens after a successful upload

Pruning used to run no matter what, so any sustained upload failure — bad
credentials, a GCS outage, a full tmp dir — silently deleted every backup
older than `RETENTION_DAYS` while the job looked healthy every six hours.

## The size-regression refusal guard

`MINIMUM_SIZE_RATIO` refuses to upload a backup smaller than this fraction
of the most recent one. The threshold is deliberately generous: a
legitimate bulk deletion (a GDPR purge, say) must not trip the guard,
while the failure it exists for shrinks an 11MB database to a few hundred
KB.

The failure this guards against: when the storage volume goes missing,
`bin/docker-entrypoint` runs `db:migrate:with_data` + `db:seed` against an
empty bind mount. That produces a valid SQLite file — not missing, not
zero bytes, only small — so `File.zero?` cannot catch it, and every later
run would upload that seeded file until `RETENTION_DAYS` had aged out
every real backup.

Comparing size against the most recent backup calibrates itself and
assumes nothing about which tables must hold rows — which matters, because
seeds do fill some of them.

## Why a refusal reports to Sentry directly

`SwayLogging.error` only writes to `Rails.logger`. Sentry's
`breadcrumbs_logger` attaches log lines to events that are already being
sent; it never creates an event on its own. A refusal means production is
probably serving a database it should not be, so it must surface
somewhere people actually watch — hence the explicit `Sentry.capture_message`
call, made only in production.

## Why backups_for_this_db anchors its regex on the timestamp

All databases share the same `db/<env>/` folder, and `"production"` is a
prefix of `"production_queue"`. Anchoring the regex on the timestamp's
year digits keeps each database matching only its own backups. The size
floor and the prune both go through this method, so that guarantee lives
in one place.

## Why the backup listing is fetched once and cached

`#backups` is fetched once and cached: the size floor and the prune both
need this list, and building it costs a network round-trip to GCS.
