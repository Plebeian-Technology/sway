---
lat:
  mode: explanation
---

# Category assignment never fails a paste

`PasteSummaryService#assign_pasted_categories` runs after the pasted summary body is already committed and the row already settled.

Nothing in this method is allowed to hand the operator a failure, because by the time it runs there is no undo: the summary is good, it is already live on the bill, and an unhandled error here would tell the operator the whole paste failed over a summary that plainly did not.

Retrying after a false failure is worse than doing nothing: the audit entry for the accepted paste was already written, so a retry writes a second `paste_summary_accepted` for one accepted paste. See [[docs/explanation/paste-summary-audit-transaction-boundaries.md|paste-summary-audit-transaction-boundaries.md]] for the same shape of problem one step earlier in the same method.

## Why the rescue is wider than the one error this method expects

The obvious failure here is `Llm::SchemaError` from `BillCategoryAssigner`, when the pasted category names don't match anything. That was, at one point, the only error this method rescued.

But the call into `BillCategoryAssigner#call` can raise more than that. That method runs `@bill.with_lock` — a `BEGIN IMMEDIATE` on SQLite in WAL mode — and `BillCategory.find_or_create_by!`, either of which can raise `SQLite3::BusyException`, `ActiveRecord::LockWaitTimeout`, `ActiveRecord::RecordInvalid`, or `ActiveRecord::RecordNotUnique`. The `Category.where(active: true)` lookup that runs in `#assign_pasted_categories` before that call can raise the first two on its own, so the rescue here is written against `StandardError`, not a specific list — the same widening `Testimony::AttachmentClassifier` makes, and for the same reason: naming every error a code path can throw is a bet that has already lost once in this codebase.

The two causes are still logged separately, because they mean different things to whoever reads the log: "the pasted names matched nothing" is an operator's mistake to fix, and "the database was busy" is not.

## An empty pasted category list does not clear the bill's categories

If the pasted JSON includes a `categories` key with an empty array, the bill's existing categories are left exactly as they are.

This is deliberate, and worth stating clearly because an earlier version of this comment claimed the opposite.

`BillCategoryAssigner` never deletes a `bill_categories` row — that is by design, not an oversight in this method. An admin already has a control that removes a category from a bill: `Bills::CategoriesController#destroy`, reachable from the bill's own screen, which does not filter by `active` — so even a switched-off category can be taken off through it. What was actually missing was any signal to the operator that pasting an empty list had done nothing; a `paste_summary.empty_categories_ignored` log line now supplies that.

This deliberately differs from how `draft_org_positions` behaves on the same kind of paste: an empty `draft_org_positions` array **does** clear the stored drafts (see [[docs/explanation/paste-summary-draft-positions-testimony-guard.md|paste-summary-draft-positions-testimony-guard.md]]). The two fields differ because `draft_org_positions` has no other route off the bill once a draft exists, while categories already have one.
