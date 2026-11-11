---
lat:
  mode: explanation
---
# The four SQLite databases

SQLite allows one writer at a time, so anything that writes on a schedule of its own is moved off the primary file rather than allowed to contend with a vote. There are four database files, and only the first holds anything a person would miss.

## What each database holds

`primary` holds the domain. `queue` holds Solid Queue's jobs, so a backlog cannot block a vote. `cable` holds Solid Cable's broadcast rows, which a pipeline run produces constantly. `cache` holds Solid Cache entries.

The last three are all rebuildable, which is why durability — Litestream
replication plus `BackupDatabaseJob` — covers the primary file alone.

`queue` is described by `db/queue_schema.rb` and loaded by `db:prepare`;
`cable` and `cache` are built from migrations instead, so the deploy's own
`db:migrate` provisions them from an empty disk with nothing to run by hand.

## Why the annotation task refuses to run outside development

The task that rewrites model annotations is registered in every environment so
that it can refuse and say which one it needs, rather than not existing.

The gem's own version simply skipped registration elsewhere, so running it
reported that the task name was unknown. That reads as a typo rather than as a
wrong environment, and it sends a reader looking for the underlying
command-line tool instead — which checks no environment at all and is therefore
the real danger.

The environment matters because the annotations are built from whichever
database configuration loads. Development and production each declare two
databases, while test declares a single unnamed one, so the tool writes a
database name in one and omits it in the other. Running it against test
rewrites every annotated model, spec and factory to describe a layout the
application does not use where it counts, with most of the re-annotated files
pure collateral damage. It is an easy trap when
Docker is down, because the development database lives in a container volume
and test is then the only environment that can connect.

## Page size remains a measured decision

Production retains its 4096-byte page size until representative evidence from the target hardware exists. A larger compile-time default cannot establish that larger pages help this workload.

A comparison on a development machine does not prove latency or memory behavior on the deployment host. A benchmark decision requires isolated
disposable copies and real query shapes; pristine snapshots remain immutable
inputs under [[snapshot-verification]]. No live migration is authorized by
that benchmark issue.

The configured connection cache counts 2000 pages, so increasing page size also
increases its byte capacity. The 64 MiB mmap limit on the primary database (with
mmap disabled on the auxiliary queue, cable, and cache databases) and the OS
cache further affect read timings. A fair report identifies these effects instead
of interpreting every timing change as fewer SSD reads.

SQLite cannot change page size through VACUUM while the database is in WAL
mode. A disposable benchmark copy must leave WAL mode before its page-size
change and rebuild, then return to WAL with the resulting settings verified.
This restriction comes from [SQLite's VACUUM documentation](https://www.sqlite.org/lang_vacuum.html);
it is not a reason to alter a live database during measurement.

## Why default pragmas keep temporary storage in memory

`default_pragmas` sets `temp_store: "MEMORY"` across the primary and auxiliary SQLite databases so temporary tables, indices, and sort buffers stay in RAM rather than writing scratch files to disk.

Complex analytical queries, `GROUP BY` aggregations, and `ORDER BY` sorts on multi-join views otherwise spill temporary B-trees into `/var/tmp` or container overlay filesystems. Keeping temporary storage in memory eliminates scratch-file I/O on the Raspberry Pi host while every database inherits the setting through the shared YAML anchor.

## Why Action Cable runs on Solid Cable, not Redis

Action Cable uses the Solid Cable adapter because production runs no Redis at all, so a broadcast used to raise `Redis::CannotConnectError` and kill the job firing it.

There is no Kamal accessory for Redis, no `REDIS_URL`, and the Pi runs none — so, for example, `RunLegislationPipelineJob` broadcasting to `PipelineRunChannel` used to die on every run.

## Why cable messages don't live on the primary database

Solid Cable sends a message by inserting a row, and SQLite allows one writer at a time, so while `solid_cable_messages` sat on the primary database every broadcast competed for the same write lock as user votes.

A legislation pipeline run broadcasts constantly — once per run-state change, once per bill, once per activity-log entry — and that contention is real. `config/cable.yml` now names the `cable` database from `config/database.yml`, so broadcasts write to `storage/<env>_cable.sqlite3` instead; measured in development, a broadcast left the primary row count unchanged and appeared in the cable database. Moving it does not remove CPU or Puma contention, and both files still share one disk and one CPU — it is a durability and hygiene improvement.

## What sets the cable polling interval and its retention

The listener polls twice a second, a figure squeezed from both sides, and the
retention window is decided by something else entirely.

Slower polling is cheaper: the listener thread in each process holding a
subscriber costs a share of a core that falls steeply as the interval grows. The
floor comes from the screens, which are specified to converge within one
second, and the partial reload a broadcast triggers needs part of that second
too. Half a second leaves room for both.

Retention is not a delivery guarantee. A subscriber never reads a message sent
before it subscribed, because each channel starts at the highest id existing at
the moment it subscribes. Retention past the poll window therefore delivers
nothing to anyone; it only decides how long already-delivered rows sit on disk
before the trim removes them.

## Why every test worker gets its own database file

The test database path is composed from two variables, so each run gets its own
directory and each parallel worker its own file inside it.

Two containers sharing one file corrupted each other's runs: the
failures were busy-database exceptions, and they cleared the moment the other
container exited. A directory per run and a file per
worker removes the sharing rather than trying to serialise around it.

Empty has to count as unset in both. The container tooling's default-value form
sets a key to an empty string rather than leaving it out, and treating that
empty string as a real value writes every worker's database to the container
root — off the storage volume, and discarded when the container exits.

## Why cable and cache are provisioned by a migrations path

Both `cable` and `cache` declare a `migrations_paths` in `database.yml` rather than a schema file, so the deploy's existing `bin/rails db:migrate` provisions a machine built from an empty disk with nothing to run by hand.

The alternative — a schema file loaded by `db:prepare` — is the arrangement the job queue still uses, and it is what cost three failed deploys: `db:prepare` decides a database is set up by looking for a bookkeeping table, and a failed `db:seed` creates that table by itself, so one bad deploy leaves the database half made and every later deploy fails identically. `QueueDatabaseSetupService` exists to work around exactly that; a migrations path sidesteps the problem rather than compensating for it. The queue database is built from `db/queue_schema.rb` by `db:prepare` and `sway:setup_queue_database` and [[auxiliary-databases#Why the queue database names a migrations path|names a migrations path of its own]], which `cable` reached first. The provisioning spec's `"provisions the messages table from the deploy's own migrations"` example deliberately does not assert which database cable uses; it asserts the rule that has to hold either way, that whichever database a table lives on needs a `migrations_paths` so the deploy's own `db:migrate` creates it, and it was written before the cable move so the move would not have to edit it.

## Why the queue database names a migrations path

`config/database.yml` gives the queue database `db/queue_migrate`, because a config that names no path falls back to `db/migrate`, and Rails migrates every config that has pending versions.

While the key was absent, the queue pool reported `migrations_paths ["db/migrate"]` and every migration in the application's history as pending. `db:migrate` — the deploy runs it as `db:migrate:with_data` — would have run all of them against the background-job database and then dumped `db/queue_schema.rb` from the result. What prevents that is the folder being absent: a `MigrationContext` over a folder holding no files finds nothing to run, so the key read exactly like one that worked while doing nothing at all.

The folder now holds the Solid Queue 1.7 batch-tables migration, copied from the gem's own upgrade template and guarded by `table_exists?` and `column_exists?`, so a queue database that already carries those tables runs it as a no-op. `QueueDatabaseSetupService`'s `:extended` path stays for a queue database that predates the migration, which is repaired at boot rather than by a migrate run.

## Why the queue schema file cannot be hand-edited

A table added to `db/queue_schema.rb` by hand disappears on the next `db:migrate`, because the migrate run dumps the live database back over the file.

Rails dumps a schema file for every database it migrates regardless, and what it dumps is whatever that database actually contains, so a table written only into the file and never into the database is deleted rather than preserved.

That is how the Solid Queue batch tables were lost twice in two days: `solid_queue_batches`, `solid_queue_batch_executions` and the `batch_id` column were written straight into the file, the queue database never gained them, and the next dump removed all three again. A migration run against the queue database would put them in the database first, which makes the dump write them back rather than take them away — the arrangement [[auxiliary-databases#Why cable and cache are provisioned by a migrations path|cable and cache already use]], and what [[auxiliary-databases#Why the queue database names a migrations path|`db/queue_migrate` now does]].

## Why test keeps cable on the primary database and gives cache none at all

`config/cable.yml` gives test `adapter: test` with no `connects_to`, and `config/cache.yml` gives test no `database` key, so neither auxiliary database exists for a spec run.

`SolidCable::Record` calls `connects_to` only when the current environment's cable config declares one, so in test the model stays on the primary connection, which since the second cable deploy carries no `solid_cable_messages` table at all; the in-memory test adapter writes no rows, and it is what `have_broadcasted_to` reads — a cable database for test would be a file nothing opens. Test runs `:null_store` for the cache, so that one spec cannot see what another cached; `SolidCache::Record` never receives a `connects_to`, and no cache file is created for test at all.

## The cable move ships in two deploys

`solid_cable_messages` exists on the cable database alone. It got there as a two-deploy cutover, so a bad first deploy could be undone by reverting one config file.

The first deploy pointed cable at the new database and left the primary table in place, unwritten and unread, which is what made that single-file revert enough. The second dropped the primary table, once it had stopped growing. The table's shape is still checked against the gem: it mirrors the `db/cable_schema.rb` template Solid Cable itself ships (binary `channel`/`payload`, `channel_hash`, `created_at` only, no `updated_at`), and `spec/config/cable_spec.rb` compares the column lists in the two files on every run. It reads the checked-in dump rather than a live table because no cable database is open during a spec run, and the dump is regenerated from the real cable database by `db:migrate`. A gem upgrade that adds a column is reported by that spec rather than by a broadcast failing on the Pi.

## A backup that shrank is refused rather than uploaded

An upload is refused, and no old copy is pruned, when the file being backed up has fallen below a floor derived from what the last one held.

The failure this guards is not corruption but a healthy-looking replacement: the
storage volume disappears, the container's entrypoint reseeds the database, and
the next backup faithfully uploads the seed file over the history it should have
been protecting. Emptiness is not the test, because a seeded database is valid
and non-empty — so a size check against the previous copy is what can tell them
apart, and refusing to prune matters as much as refusing to upload.

## A machine not serving the public writes no backups at all

The boot-time guard has a second half, separate from the once-per-deploy bound described in [[standby-restore#Why a deploy makes at most one backup copy]].

Every machine writes into the same shared backup history, and a machine that is
not serving the public holds a seed-built database. Its copies would push the
real ones out as they age past the retention window, so a machine told to skip
refuses entirely rather than merely skipping its first run.

## Why the queue database is left out of the backup deliberately

The background-job database is not backed up either, and unlike cable and cache that is a decision about what restoring it would do rather than about whether the rows matter.

A copy of the queue is always older than the primary database it would be
restored beside, so the jobs in it describe work the restored primary has
already recorded — and re-running them could send the same message to the same
person twice. The exclusion is asserted rather than merely left unwritten, so
putting the queue back has to be somebody's decision instead of an accident.

## Backups and replication treat cable and cache as disposable

`BackupDatabaseJob#database_names` and `config/litestream/litestream.yml.erb` name only the primary database, leaving cable and cache out of both replication and backups.

Cable messages are ephemeral pub/sub inside a ten-minute retention window, and a cache is rebuildable by definition, so replicating or backing up either would copy bytes nobody would ever restore — cache is likewise absent from the `config/recurring.yml` allowlist.

## The Solid Cache database replaces two different broken caches

Solid Cache is the third sibling of Solid Queue and Solid Cable — a Rails component that keeps `Rails.cache` in a database table instead of a separate service, needing no new container and no memory on the Pi.

All three siblings are declared unversioned in the `Gemfile`, matching each
other, with the lockfile pinning the exact build.

Production used `:file_store` at `tmp/cache`, inside the container: wiped on every deploy, with the web and job containers each keeping their own private copy, so a value a job wrote was invisible to a request. Development used `:memory_store`, held in the Rails process heap: gone on reload, and not shared between processes either. Solid Cache gives both environments one mechanism, and because its database file lands in `storage/` — the volume Kamal mounts into both containers (`deploy.yml`, `sway_storage_dir:/rails/storage`) — it survives deploys, and both containers read the same entries.

## Adding the Solid Cache store is a separate step from switching to it

The gem, the database entry and the table landed before `config.cache_store` changed, so a production cache problem could be rolled back without also reverting development.

Development switched first and production second, each as its own commit so either can be reverted without the other, and the ceilings arrived on their own in a third commit — see [[auxiliary-databases#What bounds the cache database's growth]]. `config/cache.yml` is what tells Solid Cache which database to use, and it is read on every boot regardless of what `Rails.cache` is set to, because it is what gives `SolidCache::Record` its connection. That is what made the staging possible: the store existed, connected and unused, for as long as the switch took.

## Why development's cache has to be a real store

Passkey challenges, the SMS verification token and the rate-limit counters are written by one request and read by the next, so a development cache that quietly drops writes breaks sign-in and registration outright rather than merely slowing them.

That is why `:null_store` has never been an option in development: it would
silently sever `/sessions/challenge` from `/sessions/callback`, and phone
verification from registration, with no error anywhere to say so. The
`bin/rails dev:cache` toggle is unrelated — it gates fragment caching and the
long-lived asset `Cache-Control` header, not which store `Rails.cache` uses.

Solid Cache satisfies the requirement more completely than the `:memory_store`
it replaced. A heap-held cache also lost every challenge on a code
reload, which is frequent in development, and was invisible to a second process;
entries in a database file survive both.

## What bounds the cache database's growth

`store_options` gives Solid Cache two ceilings — a one-week `max_age` and a 128 MB `max_size` — so the cache file cannot grow without limit on a Pi whose single disk also carries the primary database.

Solid Cache trims as it writes rather than on a schedule, so an unbounded cache announces itself only once the disk is full. What fills alongside it is the primary database, the one file here that no rebuild can replace, which makes an unbounded cache a durability problem rather than a housekeeping one.

The age ceiling discards whatever nobody has read for a week, which is the ordinary case. The size ceiling is the backstop for the case the age ceiling cannot catch: a burst of writes arriving faster than a week of staleness accrues.

Both live under a `store_options` key rather than beside `database`, because `SolidCache::Configuration` takes a fixed keyword list: a ceiling written one level too high raises `ArgumentError` before the app finishes booting.

Both ceilings sit in one YAML anchor that development and production inherit, because a bound that differed between the two would mean a value evicted in production yet still answering in development — the class of difference that makes a cache bug reproduce nowhere. Test inherits neither, having no cache database at all.

## Why the cache database is not copied off the server

The cache holds personal data in plain key text, so it stays on the Pi rather than coming down with the primary database.

`sms_verified_token:<token>` maps a single-use bearer proof to the phone number
it proves ownership of, and the phone-verification throttle keys its counter on
the normalised phone number itself; WebAuthn challenges and caller IP addresses
sit alongside them. `scripts/pull-prod-db.sh` trims personal data on the server
before anything is sent, but it does that by walking the primary database's
declared links to `users`. `solid_cache_entries` has one opaque binary key
column and no declared links at all, so none of that machinery can see inside
it — adding the cache database to that copy would put every guarantee the
script makes out of reach at the point it mattered most. The entries expire on
their own anyway, which is what makes leaving them behind cost nothing.

The queue database is the one auxiliary database that does come down, under its
own flag, because a failed job's error and backtrace live there and nowhere else
— `active_job_report_on_retry_error` is false, so a job that fails and is retried
is never reported to the crash reporter. It travels redacted rather than
filtered: job arguments survive only for an allowlist of classes read and found
to name nothing but bills, legislators, pipeline runs and jurisdictions, so a job
class written later is redacted by default rather than sent by default.

## How a table the schema file gains reaches a database that already exists

`db:prepare` fills a queue database that holds nothing, and does nothing to one that already holds jobs, so a table Solid Queue adds in a later version reaches a fresh disk and no other machine.

`QueueDatabaseSetupService` closes that gap on the boot that follows the
upgrade. It builds a throwaway database from `db/queue_schema.rb` under `tmp/`,
reads the `CREATE` statements back out of it, and runs the ones whose table the
live queue database does not have. It only ever creates: nothing is dropped,
no column is altered, and a table that is already there keeps its rows. The
outcome it reports is `:extended` rather than `:created`, which is what
separates a repair from the first build.

What that path does not carry is a column added to a table that already exists.
Solid Queue 1.7 added `solid_queue_batches` and `solid_queue_batch_executions`
alongside a `batch_id` column on `solid_queue_jobs`, and only the two tables
arrive this way. The column arrives with the migration under `db/queue_migrate`
instead, which is the reason that folder holds one. The gem's own upgrade note
calls the whole change optional until Solid Queue 2.0 — everything works as
before, batches aside — so nothing was waiting on either half.

Loading the schema through `db:schema:load` was never an option: that task
refuses to run against production at all, and the refusal is right, because
loading a schema over a database that has tables destroys them. The service
loads the whole file only into a queue database with nothing in it, and reaches
a database that already holds jobs by copying the missing tables one at a time.

The throwaway database it reads those statements from lives under `tmp/` and is
deleted again in an `ensure`, along with any `-wal` and `-shm` sidecars, so a
boot leaves nothing behind that a later boot could read as real.

`sway:setup_queue_database` in `bin/docker-entrypoint` is what runs this, after
`db:migrate:with_data` and `db:prepare`.
