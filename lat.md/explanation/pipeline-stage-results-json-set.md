---
lat:
  mode: explanation
---

# Why record_stage_result uses an atomic json_set

`RunLegislationPipelineJob#record_stage_result` uses SQLite's `json_set` to merge one key into `stage_results` in a single atomic SQL statement.

An earlier read-modify-write version (reload, merge in Ruby, `update_columns`) narrowed but did not close the race window — a concurrent writer (the operator console, a single-bill refresh) could still update between the reload and the write. With `json_set`, the WAL (write-ahead log) writer lock holds for the whole statement, so concurrent writers serialize through SQLite itself.

Side benefit: no ActiveRecord object is built, so no association cache gets invalidated.

## The DAG_ORDER allowlist

The JSON `pointer` argument is passed as a bound parameter (`?`) to the `update_all` call, so SQL injection through the path argument is already blocked by the SQLite driver's parameter binding.

`record_stage_result` still checks `stage` against the `DAG_ORDER` allowlist, to guard against two other things:

- Malformed JSON path syntax — SQLite's `json_set` silently no-ops on a bad
  path (it does not raise), which would leave `stage_results` unwritten
  while the caller assumed success.
- A future refactor inlining the pointer back into the SQL string literal,
  where bound-parameter protection would disappear.

Failing fast here is cheap next to a silently corrupted `stage_results` column.

## Why the key set is checked against the real method, not a hand-typed fixture

`record_stage_result` writes the per-stage timestamp under the key `"at"`, never `"finished_at"`.

`ResourceCachePanelSerializer` carries a comment saying so, but nothing called the real method and checked — every fixture in the spec suite typed `"at"` by hand, so a renamed key would have broken none of them. `spec/jobs/run_legislation_pipeline_job_spec.rb` closes that gap by calling `record_stage_result` itself and asserting the returned key set (`match_array(%w[status at])`, and `%w[status at error reason])` when `error:`/`reason:` are passed) instead of asserting against a hand-constructed hash.
