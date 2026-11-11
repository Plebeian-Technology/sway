---
lat:
  mode: explanation
---

# PipelineRunStage design notes

Explains why PipelineRunStage's serialized array columns have no default, and why mark_bill_completed! relies on with_lock under SQLite WAL mode.

## Why the serialized array columns have no default

`completed_bill_external_ids` and `remaining_bill_external_ids` are declared with `serialize ..., coder: JSON` and no `default:`.

That is on purpose: the `completed_bills` and `remaining_bills` helper methods wrap the raw value in `Array(...)`, which turns `nil` into `[]`, so callers always get an array back regardless of what the column holds.

## Why mark_bill_completed! takes a row lock

`#mark_bill_completed!` moves one external id out of the remaining list and into the completed list in a single step that no caller can observe half-done.

If the id is not in the remaining list, the method changes nothing and returns, so calling it again with the same id is harmless.

It reaches for `with_lock` because, on Rails 8 with SQLite in WAL mode — where transactions open with `BEGIN IMMEDIATE` — that lock genuinely makes concurrent writers take turns, rather than only guarding against interleaved reads the way a lock would under a different isolation model.
