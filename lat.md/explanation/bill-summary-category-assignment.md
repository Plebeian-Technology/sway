---
lat:
  mode: explanation
---

# Category assignment error handling in GenerateBillSummaryJob

`GenerateBillSummaryJob#perform` assigns 1–3 active categories BEFORE `mark_completed!`, so a category failure leaves the provisioning row in `generating` (not `completed`).

The ordering is load-bearing — the assigner MUST run before `mark_completed!`. `BillCategoryAssigner.new` takes POSITIONAL arguments.

## When the taxonomy is empty

When the taxonomy is empty (all categories deactivated or never seeded), `#perform` skips the assigner entirely and logs a warning.

Routing an empty active-set through the assigner raises `Llm::SchemaError` → `DeterministicBillSummaryError`, which would mark a perfectly valid summary as failed. When no taxonomy exists, the only possible outcome is "uncategorized" — so the bill is left `completed`, and the boot backfill can categorize it once categories are re-seeded or reactivated.

## When the response has no categories

When the LLM response omits the `categories` key entirely (`nil`) or returns an empty array, the bill COMPLETES uncategorized — the boot backfill (`BackfillBillCategoriesJob`) will categorize it later.

`#perform` does NOT raise here; a missing or empty `categories` key means the model made no claim about categories.

## When the response names categories that do not exist

Neither does a non-empty array that matches nothing in the active set raise. `Llm::SchemaError` carries two different meanings, and the category assignment call site is on the wrong side of the split:

- Raised inside an adapter, it means "the model's response violated the
  wire contract" — that happens BEFORE anything is persisted, so
  `DeterministicBillSummaryError` → `discard_on` is the right policy:
  nothing of value is lost, and a retry would only pay again for the same
  deterministic failure.
- Raised HERE, at the category assignment call, it means "the model named
  categories this taxonomy does not have" — and by this line the
  summary, the breakdown, the citations, and the positions are all
  committed and paid for.

The outer rescue ladder cannot tell the two apart, so before this fix it applied the PRE-persist policy to a POST-persist failure: the row landed `failed` carrying a perfectly good `llm_summary`, `BillCreatorLlmSummaryStatus` routed `failed` to `LlmSummaryGenerateBranch` (which never renders `llm_summary`), and the operator's only available action — Retry — paid for both calls again.

This is the same argument the positions rescue makes for itself (see [[docs/explanation/bill-summary-positions-error-handling.md|bill-summary-positions-error-handling.md]]): "the summary has ALREADY been paid for and persisted by this point, so discarding ... destroys value that was bought." `PasteSummaryService` and `BackfillBillCategoriesJob` both already rescue this exact call. Three call sites, one policy.

## The trade-off, stated rather than buried

`BackfillBillCategoriesJob`'s filter excludes rows whose `generation_status` is `failed`, on the rationale that a mismatch re-fails identically and re-burns a metered call every boot.

Completing uncategorized instead of failing puts these rows back INTO the backfill set. That is deliberate and is not the same bet: the backfill sends `BillCategoryPromptBuilder`, which enumerates the active taxonomy and constrains the response with `BILL_CATEGORIES_SCHEMA`, so it is materially more likely to match than this call's freeform `categories` key on the summary schema — it is the DESIGNED remedy for an uncategorized bill. The leftover cost is one cheap categorize call per boot for a bill the constrained prompt also cannot match, which the backfill's own per-bill rescue already absorbs. Paying that beats stranding a bought summary in a status its UI refuses to render.

(The matching comment in `backfill_bill_categories_job.rb` still describes the old `failed` behaviour and needs the same edit; that file is being handled separately.)

## generation_error and the parsed-is-nil case

`generation_error` is deliberately NOT written when category assignment fails or is skipped.

`generation_error` is deliberately NOT written when category assignment fails or is skipped: the positions rescue's rule is that a COMPLETED row's `generation_error` can only have come from that rescue, and `LlmSummaryPositionsErrorNotice` reads it on exactly that basis. A category mismatch is not a positions failure, so it belongs in the log and nowhere else.

`parsed` is `nil` when the summary call was skipped for want of source text. No response exists to read categories from, and logging "the model returned nothing" for a call that was never made would put a false statement in the log — the skip already has its own log line (`generate_bill_summary.no_source_text`).
