---
mode: explanation
summary: "Why TestShardDatabases copies a template instead of reloading per worker, and the WAL-mode and stale-sibling traps its copy methods guard against."
status: agent-extracted
related: []
---

<!-- vale Vale.Spelling = NO -->

# TestShardDatabases design notes

`Sway::TestShardDatabases` (`lib/sway/test_shard_databases.rb`) gives every
`parallel_tests` worker its own SQLite database, copied from one template.

## Why copying, not reloading per worker

Every worker copies from the one template rather than each worker paying
its own `db:schema:load`.

`TestShardDatabases` is constructed with worker 1's database path — the
template `config/database.yml` already resolves to when `TEST_ENV_NUMBER` is
unset. It only reads and copies files itself; the caller (the
`sway:test:prepare_shards` rake task) decides whether the schema needs
loading first.

## Why worker_paths numbers workers the way it does

`#worker_paths` returns the path for each worker from 1 to `count`: worker
1 is the template itself, because `parallel_tests` leaves `TEST_ENV_NUMBER`
unset for the first process. Every worker after it gets the template's own
directory and base name suffixed by its number — the exact rule
`config/database.yml` already applies through `TEST_ENV_NUMBER`, so a
worker's database path here matches the path Rails resolves for it.

## What `+label+` carries in `#copy_out`

What else `+label+` has to carry, beyond the worker number, is the caller's
to decide: `sway:test:lane` puts the verify run's id in front of the lane
name, because two red runs in a row would otherwise leave only the second
one's databases.

## Why `#checkpoint_and_disconnect!` runs before every copy

This repo already hit the WAL-mode copy trap once, in the production
snapshot harness: a template copied while a connection was still open was
missing newly added columns, because a database's most recent writes sit in
the separate `-wal` file until connections close.

## Why `#copy_sqlite_main_and_wal` clears the destination first

Clearing any `-wal`/`-shm` already at `+dest+` before copying means a stale
sibling left over from an earlier copy at this same path can never sit
beside a freshly overwritten main file — that pairing is its own kind of
corrupt read, distinct from (and just as real as) the checkpoint-ordering
trap above.

`#copy_sqlite_main_and_wal` never copies the `-shm` file itself: a new
reader rebuilds it, and a stale one corrupts what gets read.

## How `spec/tasks/sway_test_shards_spec.rb` is built, and what it proves about checkpointing

The spec drives `Sway::TestShardDatabases` directly rather than through
rake, so its examples are fast and do not depend on rake's task graph
. The class does not exist until task 2 of the plan that introduced
it, so every reference goes through `Object.const_get`/`const_defined?`
rather than a literal `Sway::TestShardDatabases` constant — a literal
reference would make `bin/steep check` warn `Ruby::UnknownConstant` during
that RED phase, and the plan requires Steep to stay at zero warnings even
before the class exists.

The checkpoint-before-copy example is backed by a measurement and two
mutation proofs. A real WAL-mode database with one row
written after the last checkpoint, copied by main file only (no `-wal`
sibling, no checkpoint), yields a copy that sees only the pre-existing row,
missing the new one. The identical copy taken after `PRAGMA wal_checkpoint(TRUNCATE)`
sees both rows. This is the same failure
`spec/support/production_snapshot.rb`'s `checkpoint_and_disconnect!`
already carries a comment about (a template copied while a connection was
open was missing newly added columns).

Mutation-proved, twice: reordering `#prepare` to copy before
checkpointing failed the example with "FileUtils received :cp out of
order"; deleting the `checkpoint_and_disconnect!` call entirely failed it
with the same message (the still-pending ordered expectation is never
satisfied, so the first real call is "out of order" by definition).
Restoring the original code passed it again both times.

## Why `sway:test:lane`'s spec expects `SystemExit`, and what its exclude-guard example actually proves

`spec/tasks/sway_test_shards_spec.rb` drives `Rake::Task` directly rather
than shelling out, so it stays a fast unit spec. `Kernel.system` and the
sub-tasks are stubbed for the two known-lane examples because the real
task ends every path (success and rejection alike) in `Kernel#exit`, which
would otherwise tear down the rspec process — `expect { ... }.to
raise_error(SystemExit)` is what lets the example survive it.

Four facts decide which specs each lane runs, and an example that only
checks the command ran would still pass with the whole command array
deleted. The concrete slip the "runs `lane` against its own directory, and
excludes `spec/system` from the non-browser lane only" example catches is
swapping the exclude guard to the other lane: the browser lane would then
get `spec/system` minus `spec/system` — zero files, which the gate does
catch — while the non-browser lane picked up all of `spec/system` WITHOUT
`SWAY_REQUIRE_BROWSER`, where a missing browser makes every one of those
examples skip and the lane still reports a healthy count.
