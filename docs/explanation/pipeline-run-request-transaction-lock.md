---
mode: explanation
summary: "Explains why BillsController wraps the active-run check and the LegislationPipelineRun create in one requires_new transaction, and how SQLite's IMMEDIATE mode makes that safe without row locks."
status: agent-extracted
related: ["docs/reference/legislation-pipeline-concurrency-layers.md"]
---

<!-- vale Vale.Spelling = NO -->

# The request-level active-run check and its transaction lock

`BillsController`'s shared pipeline-enqueue helper checks whether any
pipeline run is already active (`LegislationPipelineRun.active_any`) and
creates the new row inside one `requires_new: true` transaction, so nothing
can slip between the check and the create.

Rails opens that transaction with `BEGIN IMMEDIATE` — set by
`default_transaction_mode` in `config/database.yml` — which takes SQLite's
write lock the moment the transaction begins. Two admins clicking at the
same moment therefore queue up one behind the other, and the second one's
check sees the first one's row. The worst case is a wait that times out,
never two runs. SQLite ignores row-locking clauses such as `FOR UPDATE`,
which is why the check leans on the transaction mode instead of a row lock.

## Why the check uses `active_any`, not `active_global`

The check made before queuing a run used to call `active_global`, which
only sees runs with `bill_id` nil. A run covering a single bill slipped
past it, so a new all-bills run could be accepted alongside it, and the
clash surfaced only later, when Solid Queue refused the job — by which
point the row already existed. The check has to use `active_any`, so any
run still in flight, single-bill or all-bills, blocks a new request
.

Behind all that, `RunLegislationPipelineJob` declares
`limits_concurrency to: 1, on_conflict: :raise`, and the controller turns
the resulting error into the same 409 duplicate-run response. This
transaction is the request-level half of that guarantee; see
[Legislation pipeline concurrency layers](../reference/legislation-pipeline-concurrency-layers.md)
for the job-level lock, the database schema layer, and the cross-run Bill
upsert that back it up further downstream.
