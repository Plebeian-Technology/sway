---
lat:
  mode: reference
---
# Snapshot verification

Production snapshots are immutable inputs to isolated verification copies.

- Never open or migrate the pristine SQLite files in `db/`; even opening WAL-mode SQLite may write. Copy the primary and queue snapshots first.
- An isolated run mounts only the scratch copies as storage and retains required read-only data mounts. Confirm command working directory and mount targets before execution.
- Snapshot files are untracked and may be missing from worktrees or fresh clones. A skipped snapshot example is unverified coverage.
- Place opt-in variables inside the container invocation as supported by the current harness; a host prefix may not reach dip.
- Inspect generated schema and annotation changes afterward. A production-derived schema can contain snapshot-only tables and must not replace the project schema.
- Current implementation: `spec/support/production_snapshot.rb` and `spec/production_readiness/`.
