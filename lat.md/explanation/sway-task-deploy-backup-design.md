---
lat:
  mode: explanation
---

# Why SwayTask.backup_db retries

`SwayTask#backup_db` (`lib/tasks/sway_task.rb`) retries a few times when `DatabaseBackupService` reports `:skipped`.

The retry loop belongs here because at deploy time the storage volume may still be mounting, so trying a few times gives the database file a chance to show up before the task gives up.

## Why BackupDatabaseJob exists

Before `BackupDatabaseJob`, backups only ran at production container start (`SwayTask#backup_db`), so between deploys the worst-case data loss was days or weeks. The job runs every few hours via `config/recurring.yml`.

`SwayTask#run_task` invokes `backup_db` only in `production`. Per-database failures are caught and logged so one bad source never blocks the other.

## Why BackupDatabaseJob only backs up the main database

`BackupDatabaseJob` deliberately does not copy the Solid Queue database, which holds background jobs. Litestream leaves it out too, for the same reasons.

A copy of it would not be safe to restore. The main database is now copied continuously, so any job-queue copy is minutes or hours older than the main database you would put back next to it. Running those old jobs again against newer data could send the same text message or notification twice, which is worse than losing the jobs.

And there is not much to lose. `db:migrate` rebuilds the tables, and the repeating jobs are read back from `config/recurring.yml` when the app starts. What actually disappears is jobs that were half-finished, and an old copy could not have brought those back in a usable state anyway.

To undo this, return `[main, "#{main}_queue"]` from `#database_names` — the service takes any database name and does nothing when the file is not there. `main` is spelled out as a variable for exactly that reason: the instruction here used to name a variable that did not exist, so following it literally did not work.

## Why download_email_blocklist bounds its network wait and keeps the existing file

[[lib/tasks/sway_task.rb#SwayTask#download_email_blocklist]] passes `open_timeout` and `read_timeout` to `OpenURI.open_uri` and rescues network and timeout errors during `rake sway:deploy`.

Because `OpenURI.open_uri` buffers the full response before `IO.copy_stream` opens `tmp/blocklist.conf`, a DNS or timeout failure leaves any existing blocklist file on disk intact (and `User::EmailValidator` falls back to its built-in domain list when none exists) instead of aborting `sway:deploy`.
