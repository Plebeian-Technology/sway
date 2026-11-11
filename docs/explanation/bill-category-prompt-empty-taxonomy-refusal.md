---
mode: explanation
summary: "Why BillCategoryPromptBuilder#initialize raises on an empty active_categories list instead of degrading, unlike its sibling BillSummaryPromptBuilder."
status: agent-extracted
related: ["docs/explanation/bill-summary-prompt-security.md"]
---

# Why BillCategoryPromptBuilder refuses to build a prompt from an empty category list

<!-- vale Vale.Spelling = NO -->

`BillCategoryPromptBuilder.new(bill, active_categories:)` raises
`ArgumentError` when `active_categories` is empty, rather than rendering a
prompt anyway.

## The prompt that used to be built

An empty active set has no honest prompt here, so it is refused rather than
rendered. `#system_prompt` used to interpolate the joined list
unconditionally — "Choose only from this exact list: " followed by "Never
return an empty list" — which amounts to "pick from nothing and never return
nothing", and the only compliant answer is invented names.

## Why the sibling builder does not do the same

The sibling `BillSummaryPromptBuilder` degrades instead of raising, because
`categories` is OPTIONAL on `BILL_SUMMARY_SCHEMA` and that call has other
work to do. Neither is true here: `BILL_CATEGORIES_SCHEMA` requires
`"categories"` with at least one item, and categorizing is the whole call. A
prompt against an empty category list can only produce a response
`BillCategoryAssigner` then rejects, for the price of a paid call.

## Why this is a class-level guarantee, not caller discipline

`BackfillBillCategoriesJob` already returns before reaching here (its own
guard), so nothing in production hits this today — which is the point. The
precondition was held by one caller's discipline; now the class holds it for
every caller.

The `active_categories` keyword argument is required, mirroring the sibling
`BillSummaryPromptBuilder.new(bill, active_categories:)` signature so call
sites look the same.
