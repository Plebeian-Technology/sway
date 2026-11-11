---
mode: explanation
summary: "Explains why each rspec run and worker gets its own test SQLite file, since overlapping runs on one file corrupt each other, and the empty-string-vs-unset compose quirk that shaped how SWAY_TEST_DATABASE_DIR is read."
status: agent-extracted
related: [legislation-test-isolation-paths, env-read-check-design]
---

# Why `config/database.yml`'s `test:` block interpolates a per-run, per-worker path

Two rspec runs at once corrupt each other's results when they share one
`storage/test.sqlite3`: a run that overlaps another's hold on the file
reports many failures and `SQLite3::BusyException`s, and the same suite is
nearly clean once the other run clears. `test.database` is one ERB interpolation of
`SWAY_TEST_DATABASE_DIR` and `TEST_ENV_NUMBER` that falls back
to today's exact path (`storage/test.sqlite3`) when both are unset, giving
each verify run its own tmpfs and each `parallel_tests` worker its own file
on it. A later decision struck the run lock that used to sit behind this, so
`spec/config/test_database_isolation_spec.rb` is the only thing left that
would catch a typo silently putting every worker back on one shared file.

See `docs/explanation/legislation-test-isolation-paths.md` for the sibling
class that mirrors this same two-variable shape for the legislation
pipeline tree, and `docs/explanation/env-read-check-design.md` for why both
read `ENV` directly rather than through `Sway::Settings`.

## Why an empty `SWAY_TEST_DATABASE_DIR` is treated as unset, not as the filesystem root

`.dockerdev/compose.yml` declares every forwarded variable as
`NAME: ${NAME:-}`, and that form sets the key to an EMPTY STRING in the
container when the host variable is unset — the same measured behavior
`scripts/dip/verify.sh` records for `SWAY_VITE_BUILD_DIR`. `ENV.fetch`'s
default only fires for an ABSENT key, not an empty one, so if
`database.yml`'s interpolation ever followed that naive convention, every
plain `dip run rspec` would resolve to `/test.sqlite3` — the container
root, off the storage volume, discarded the moment the container exits.
The interpolation treats a blank value the same as an absent one so that
case falls back to the same default path instead.

## How the interpolation-dependent examples were verified

Several examples in `spec/config/test_database_isolation_spec.rb` were
verified by mutation, not just written and trusted —
each restored some old, broken shape and confirmed the example actually
failed against it before confirming it passes against the fix:

- Restoring the old hardcoded `database: storage/test.sqlite3` line in
  place of the ERB interpolation made
  `"resolves under SWAY_TEST_DATABASE_DIR when only the run directory is
  set"` fail (expected `"/testdb/test.sqlite3"`, got
  `"storage/test.sqlite3"`), and restoring the interpolation passed it
  again.
- That same hardcoded-path mutation also failed
  `"resolves per worker when TEST_ENV_NUMBER is also set"`. Separately,
  with the interpolation restored but its `<%= ENV["TEST_ENV_NUMBER"] %>`
  half deleted, that example failed again (expected
  `"/testdb/test2.sqlite3"`, got `"/testdb/test.sqlite3"`) WHILE the
  directory-only example above still passed — proving the two axes
  (run directory, worker number) are checked independently rather than by
  one mutation masking the other. Restoring the full interpolation passed
  it again.
- The same `TEST_ENV_NUMBER`-deletion mutation also failed
  `"gives two different TEST_ENV_NUMBER values two different files"`
 : with `TEST_ENV_NUMBER` dropped from the interpolation, both
  calls resolved to `"/testdb/test.sqlite3"` and the example's `not_to eq`
  failed. Restoring the interpolation passed it again.
- Separately, deleting `/testdb` from the rspec service's `tmpfs:` list in
  `.dockerdev/compose.yml` made
  `"declares a tmpfs list on the rspec service that keeps the inherited
  mounts and adds /testdb"` fail (expected
  `["/tmp", "/app/tmp/pids", "/testdb"]`, got
  `["/tmp", "/app/tmp/pids"]`), and restoring the entry passed it again.

## Why `/testdb`'s tmpfs entry carries an explicit `size=`

An unbounded tmpfs mount takes the kernel default, half the machine's RAM,
which competes with the memory a full `verify` run already needs.
Everything written to `/testdb` is RAM: six worker
databases with their WAL files, plus every pipeline artifact and fixture
the legislation specs write, which used to land on disk. When it fills,
SQLite returns `SQLITE_FULL` and the shard copy raises `ENOSPC`, and both
surface as unrelated-looking example failures with no line anywhere saying
"out of space". `.dockerdev/compose.yml`'s `/testdb` tmpfs entry carries an
explicit `size=` option for exactly this reason.
