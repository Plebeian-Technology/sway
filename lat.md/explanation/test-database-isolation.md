---
lat:
  mode: explanation
---
# Test database isolation

`config/database.yml`'s test block interpolates `SWAY_TEST_DATABASE_DIR` and
`TEST_ENV_NUMBER`, so a verify run gets its own filesystem and each parallel
worker its own file on it.

`spec/config/test_database_isolation_spec.rb` is what keeps it that way.

## What sharing one database file costs

Two rspec runs at once that share `storage/test.sqlite3` collide, and the
results that come back are about the sharing rather than about the code.

A run that overlaps another's hold on the file reports many failures and
`SQLite3::BusyException`s, and the same suite is nearly clean once the other run
clears.

The interpolation falls back to `storage/test.sqlite3` when both variables are
unset, which is what a plain `dip run rspec` resolves to, so the shared file is
one command away rather than gone.

## How contention presents when a run is started by hand

A run that loses the race does not fail, it never starts.

The `before(:suite)` truncation cannot take the lock, and about ten seconds
later the run ends with `0 examples, 0 failures, 1 error occurred outside of
examples`, an `ActiveRecord::StatementTimeout` wrapping
`SQLite3::BusyException`.

Exit 1 with no failures reads like a broken spec file rather than a busy
neighbour, which is what makes it expensive. A retry loop adds load to the
contended database rather than moving off it. A directory of one's own in
`SWAY_TEST_DATABASE_DIR`, prepared once, removes the contention instead of
waiting it out, and a neighbour running browser specs holds the shared file for
minutes rather than seconds.

`SWAY_REQUIRE_BROWSER=1` belongs with that move for system specs, because a run
on a fresh database with no Chrome skips every example and answers green
([[verification-gates#Known traps]]).

## Why an empty value is treated as unset

`.dockerdev/compose.yml` declares every forwarded variable as `NAME: ${NAME:-}`,
and that form sets an empty string in the container when the host variable is
unset rather than leaving the key absent.

`ENV.fetch`'s default fires only for an absent key. Had the interpolation
followed that convention, every plain `dip run rspec` would have resolved to
`/test.sqlite3` — the container root, off the storage volume, discarded when the
container exits. A blank value falls back the way an absent one does.

## Why the tmpfs entry carries an explicit size

An unbounded tmpfs takes the kernel default of half the machine's RAM, which
competes with the memory a full verify run already needs.

Everything under `/testdb` is RAM: six worker databases with their WAL files,
and every pipeline artifact and fixture the legislation specs write. A full one
makes SQLite return `SQLITE_FULL` and the shard copy raise `ENOSPC`, and both
surface as unrelated-looking example failures with no line anywhere saying the
space ran out.

## How the interpolation's examples were proved

Each example that depends on the interpolation was checked by mutation rather
than written and trusted.

The old shape was restored, the example was confirmed to fail against it, and
the fix was confirmed to pass it again.

The two axes were mutated separately, which is the part that matters. Restoring
the hardcoded `storage/test.sqlite3` broke the run-directory example, while
deleting only the `TEST_ENV_NUMBER` half of the interpolation broke the
per-worker examples and left the run-directory one passing — so neither
mutation masks the other, and one typo cannot quietly put every worker back on
a single file.

## Why a development reset may also affect the test database

Rails 8.1.4 includes the test environment when database tasks enumerate development configurations, subject to two environment guards.

The installed Active Record source adds test to the current environments for development unless SKIP_TEST_DATABASE or DATABASE_URL is set. An isolated development database name alone therefore cannot isolate db:reset. A reset preflight needs to cover either a run-scoped isolated test directory or SKIP_TEST_DATABASE, alongside the development database guard. The existing test path and worker overrides are described in [[test-database-isolation#Test database isolation]].
