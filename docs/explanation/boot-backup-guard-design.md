---
mode: explanation
summary: "Explains why BootBackupGuard exists to make the boot-time backup run once per deploy instead of once per container start, and what its safety net does not cover."
status: agent-extracted
related: [database-backup-service-design.md]
---
<!-- vale Vale.Spelling = NO -->

# Why BootBackupGuard exists

`BootBackupGuard` makes the backup that runs when a container starts
happen once per deploy instead of once per start.

## What went wrong

Every time a container starts, `bin/docker-entrypoint` runs a rake task
that backs up the database. So a container that keeps crashing and
restarting backs up every single time. Old copies
are deleted by age and not by how many there are, so a crash loop fills the
bucket with copies — and the number of copies tells you nothing about
whether backups are actually working.

## Why not just "wait 30 minutes between backups"

That sounds simpler, but it would break the reason this backup exists. It
runs right before the database migrations, so there is something to go
back to if a migration goes wrong. If a deploy happened shortly after a
scheduled backup, a time limit would skip it — and that is exactly the
copy you would want most.

## What the guard does instead

Every deploy bakes two things into the image it builds: the commit it
came from, and the time the deploy started. After a backup succeeds it
writes both to a small file. A new deploy has a pair it has not seen, so
it backs up. A crashing container restarts the same image, so the pair is
unchanged and it backs up once and then stops.

## Why the time and not just the commit

Because deploying the same commit twice is normal, not rare —
`scripts/deploy.sh` says so itself, since a failed deploy leaves its
release number unclaimed for the next attempt to reuse. Keyed on the
commit alone, the second attempt saw an id already on record and skipped
its backup. That is the worst possible moment to skip one: something has
just changed outside git to fix the failure, the database may be half
migrated, and the migrations are about to run again. The time comes from
`SWAY_DEPLOYED_AT`, which is stamped once per run of `deploy.sh`, so it
separates two deploys of one commit while staying identical across
restarts of one image.

## Where the marker file lives

In the storage folder, because that is what survives a container restart.
So if the storage disk goes missing, the file cannot be read, and the guard backs up rather
than assume a backup already happened.

## That is not a complete safety net, and it is worth knowing why

Backing up a freshly seeded database is only refused when
`DatabaseBackupService` has a previous backup to compare its size
against. It has none when this database name has never been backed up,
or when every earlier copy has aged past the keep-for-14-days limit (see
[database-backup-service-design.md](database-backup-service-design.md)).
In any of those states a seeded database uploads and old copies get
deleted. Which is exactly why a machine that is not serving the public
must be turned off with `SWAY_SKIP_DB_BACKUP`, and not left to the size
comparison to catch.

## Why SWAY_SKIP_DB_BACKUP exists, and why the default is "always back up"

`SWAY_SKIP_DB_BACKUP` turns the whole thing off, for a machine that is not
the one serving the public. A spare or practice machine starts with an
empty storage folder, so the entrypoint builds a fresh database out of
seeds — and uploading that would push the real copies out as they age
past the keep-for-14-days limit. Set it in that machine's deploy
configuration.

If the guard cannot tell which deploy this is, `#backup_needed?` always
says yes. Development and test do not set either value. One extra backup
costs a little storage; a missed backup can cost data, so the guard leans
the safe way.

## Why record_backup must only be called after a real upload

`#record_backup` must be called ONLY after a backup really reached Google
Cloud Storage. Recording a backup that was skipped or rejected would stop
this deploy from ever trying again.

A backup that worked but could not write the marker file is not worth
stopping for — the cost is one extra backup on the next restart, so the
`SystemCallError` rescue only logs.

## Why missing, blank, and unreadable `SWAY_SKIP_DB_BACKUP` all mean "back up"

Missing, blank, and unreadable text are all the same answer here — backups
stay ON. A misread that silently turns them off is the worst outcome in
this group: `Sway::Settings::Ops`'s `:boolean` caster already answers
`false`, not `true`, for anything it does not recognize, and
`spec/services/boot_backup_guard_spec.rb`'s "backs up normally when
SWAY_SKIP_DB_BACKUP is blank or unreadable text" example pins that same
fail-safe behavior at the call site that actually decides whether a backup
happens.
