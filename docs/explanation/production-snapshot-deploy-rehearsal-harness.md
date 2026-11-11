---
mode: explanation
summary: "What ProductionSnapshot is for, the rules that keep it from mutating the real snapshot file, and how to run it."
status: agent-extracted
related: [live-llm-http-policy-double-gate]
---

# Production snapshot: a deploy rehearsal harness

`ProductionSnapshot` (`spec/support/production_snapshot.rb`) tries
a deploy out on a copy of the real database before it happens for real.

`db/production.pristine.sqlite3` is an untracked copy of a production
database that a maintainer supplies. Specs tagged
`:production_snapshot` replay a deploy — every pending schema migration
AND every pending data migration, the combined `rails db:migrate:with_data`
chain that `bin/docker-entrypoint` runs on the production host —
against a THROWAWAY COPY of the snapshot, then exercise the app against the
real data.

`deploy_migrate_command_parity_spec.rb` holds the entrypoint to that same
chain: an entrypoint that ran plain
`db:migrate` with no data migrations would pass this harness, which replays
the combined chain, and still fail on the host.

That spec is deliberately not tagged `:production_snapshot`: it checks the
committed `bin/docker-entrypoint` script's text, not real data, so it needs
no snapshot, and runs in every suite run and in CI rather than being
gated behind `RUN_PROD_DB_TESTS=1`.

## Rules that must hold

- **The pristine file is never opened, not even "read-only."** Opening a
  SQLite file in WAL mode (its write-ahead log) can rewrite it, through
  recovery or checkpointing. Everything works on a copy in `tmp/` made with
  `FileUtils.cp`.
- **Opt-in only**, the same style as `RUN_LIVE_LLM_TESTS` (see
  [Live-LLM HTTP policy](live-llm-http-policy-double-gate.md) for that other
  opt-in gate). The normal suite leaves these specs out unless
  `RUN_PROD_DB_TESTS=1`, and each example also skips itself when the snapshot
  file is missing — a CI checkout has no snapshot.

## Usage

```
RUN_PROD_DB_TESTS=1 dip run bundle exec rspec \
  spec/production_readiness spec/system/production_snapshot_spec.rb
```

## Why the entrypoint also runs `db:prepare` and `sway:setup_queue_database`

`db:prepare` on the job database is measured, not assumed, to be safe to
run on the machine serving the public: `db:prepare` loads a database's
tables only when it has none, so a job left waiting in the queue was still
waiting after a second deploy ran straight over the top of it.

`db:prepare` alone is NOT enough. It decides a database is set up by looking for a bookkeeping
table, and a FAILED `db:seed` creates that table by itself — so one failed
deploy leaves the job database half made, and `db:prepare` calls it
finished from then on. On a new host,
`db:migrate:with_data` leaves no tables, the failing `db:seed` leaves two, and
`db:prepare` on the next deploy changes nothing at all. `sway:setup_queue_database`
repairs that half-made state, and runs before `db:seed` — the step that
fails without it.

## What `production_data_compatibility_spec.rb` checks

Run the app against a migrated copy of the production database. This catches crashes in serializers
and page props on data shapes that made-up test data never produces. It
also pins the promise the passkey work has to keep: every existing
production user still gets a sign-in challenge for the credentials already
stored for them.

## Why production_migration_spec.rb's helper queries come in two shapes

One migration in the chain (`20260711000010`) drops
`legislators.district_id`, `.active` and `.title`, so the queries in
`production_migration_spec.rb` come in two flavours: the ones that run
before it read the old shape, joining through districts to reach a locale;
the ones that run afterwards read the new shape, where `sway_locale_id`
sits directly on legislators and no join is needed.

`ProductionSnapshot.locale_reached_by` picks between the two shapes by
checking, on the connection AS IT IS RIGHT NOW, whether
`legislators.district_id` still exists — rather than by asking which
migration has run. A legislator's locale used to be reachable only through
the district they sat in; the legislator-locale finalize migration put
`sway_locale_id` on legislators directly and dropped `district_id`. A
snapshot taken after that migration has no such column, but a snapshot
taken from before it needs the join — a reader sampling the copy BEFORE
migrating has to ask which shape it is looking at rather than assume.
Assuming the older shape on a migrated copy fails immediately with `no
such column: l.district_id`.

## Why `ProductionSnapshot.migrate!` is built from the pending-migrations primitives, not the rake-task runner

`migrate!` runs every pending migration — both `db/migrate` and
`db/data`, mixed together in timestamp order — against the CURRENT
connection, the same combined chain `rails db:migrate:with_data` applies
on deploy. It is built on purpose from
`DataMigrate::DatabaseTasks.pending_migrations` plus `.run_migration`, NOT
`DataMigrate::DatabaseTasks.migrate_with_data` (the rake-task-level runner
that does both): `migrate_with_data` opens its own connection per database
config through `with_temporary_connection`, which does NOT see the
connection this harness swapped in by hand with
`ActiveRecord::Base.establish_connection`. `pending_migrations` and
`run_migration` go through `DataMigrate::RailsHelper.schema_migration`
(the same thing as `ActiveRecord::Base.connection.schema_migration` on
Rails 7.1 and later) and `DataMigrate::DataMigrator`, and both of those use
WHATEVER connection is currently established — which is exactly the one
this harness swapped in.

`ProductionSnapshot.pending_migrations` is the same combined list for
schema and data migrations together, exposed separately so a data
migration that was skipped or forgotten shows up here as a failure rather
than sliding past unnoticed. The `data_migrations` bookkeeping table has
to exist before the pending query runs, so it is created first; creating
it again is harmless, and a fresh copy of the snapshot has no such table
at all because it predates the `data_migrate` gem.

## Why `person_key_sql` swaps keys for names only in the Baltimore locale

`ProductionSnapshot.person_key_sql` names the person behind a legislator
row when comparing the same fact on either side of a migration run, as a
SQL fragment — outside Baltimore this is the external id, which the
migration chain never rewrites. Inside Baltimore it is the person's name
instead, because the migration chain renames each of the 16 seats onto the seat
itself — `zeke-cohen-2024` becomes `baltimore-council-president` — so the
key deliberately changes there while the human it points at does not.
Swapping keys for names ONLY in the one locale that gets renamed keeps the
exact key comparison intact everywhere else.

## Why `wrong_year_cleanup_exclusion` returns an empty clause once the cleanup has landed

The wrong-year cleanup (`db/data/20260804000001`) DELETES the
congress-sourced rows on every Congress bill a wrong-year fetch touched, so
a "votes survive the deploy" comparison must not promise those rows
survival. While the cleanup is still pending on the copy,
`wrong_year_cleanup_exclusion` returns a `WHERE` clause (for a query
aliasing `legislator_votes` as `lv`) that leaves out exactly the rows the
cleanup will delete, using the cleanup's own criterion: on a condemned
bill, every `source='congress'` row that is not inferred. Once the copy
records the cleanup as applied, the clause is empty and the exact promise
covers every row again — `production_wrong_year_congress_votes_spec.rb`
pins the deleted side separately.

## Why the template is checkpointed and disconnected before copying

While a SQLite database in WAL mode still has connections open, its most
recent writes sit in the separate `-wal` file; copying the main file at
that moment gives an out-of-date copy. Seen in practice: a template copied
while a connection was still open was missing newly added `users` columns,
and `User`'s enum failed to load as a result. `checkpoint_and_disconnect!`
folds the `-wal` file back into the main file (`PRAGMA
wal_checkpoint(TRUNCATE)`) and closes every connection before anyone
copies the file.

Because of that checkpoint, `copy_sqlite_files` normally only needs to
copy the main file — but if a `-wal` file is still there anyway, it brings
that along too, since it holds committed data. It never copies the `-shm`
file: that is a short-lived index a new reader rebuilds for itself, and an
out-of-date one would corrupt what gets read.

## Why transactional tests are turned off at the CLASS level, not from a hook

The two shared contexts set `self.use_transactional_tests = false` at the
example-group CLASS level rather than from a `prepend_before` hook, because
rspec-rails sets fixtures up inside the minitest lifecycle adapter's
around hook, which runs OUTSIDE any hook this file can register. While
that setup is running, `ActiveRecord::TestFixtures` grabs every connection
pool opened mid-example — the snapshot's pool included — through its
`!connection.active_record` subscriber, and wraps it in a transaction that
gets rolled back when the example ends. Seen in practice: 52 migrations
"applied" on the connection while the template file on disk stayed on the
old schema, because the whole migration ran inside a transaction that was
then thrown away. `setup_fixtures` reads the class-level flag, so setting
it there — rather than from any hook — stops that grab from ever
happening.

## What spec/system/production_snapshot_spec.rb checks in a real browser

A real sign-in cannot finish against the snapshot, because production
users' private passkey credentials live on their own devices, not in the
copied database. So these browser flows check the part that matters for a
deploy instead: the server still treats every existing user as someone who
HAS a passkey, and never pushes them into SMS verification — which to a
user would look like their account had vanished. They also check that
real production content still renders.
