---
lat:
  mode: reference
---

# GenerateBillSummaryJob.perform return values

`GenerateBillSummaryJob#perform(bill_id)` returns one of two symbols so that a caller (chiefly `RunLegislationPipelineJob`) can tell what actually happened, rather than assuming success from a normal return.

| Value | Meaning |
| --- | --- |
| `GenerateBillSummaryJob::NOT_RUN` (`:not_run`) | No summary was produced, and none is owed by this execution. The caller must not record the stage as done. |
| `GenerateBillSummaryJob::SETTLED` (`:settled`) | This execution settled the provisioning row, whatever it settled it to (`completed`, `failed`, or a stand-down onto an operator's paste). |

- See also: [[docs/explanation/bill-summary-perform-return-contract.md|../explanation/bill-summary-perform-return-contract.md]] for why this distinction exists and what broke without it.
