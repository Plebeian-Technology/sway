---
mode: explanation
summary: "Explains the uncategorized-bills scope in BackfillBillCategoriesJob, why it keys off active categories instead of any category row, and how the taxonomy-mismatch stamp keeps a no-match verdict from becoming permanent."
status: agent-extracted
related: []
---
<!-- vale Vale.Spelling = NO -->

# Why the uncategorized-bills scope in BackfillBillCategoriesJob looks the way it does

`BackfillBillCategoriesJob` runs the CATEGORIZE-ONLY LLM pass
(`BillCategoryPromptBuilder` / `adapter.generate_bill_categories`) over bills
that already have a stored `llm_summary` but no active category. It never
re-summarizes a bill, so its API cost scales only with how many bills are
still uncategorized — normally zero except on the first boot after a
deploy, since it is enqueued at every boot.

## "Uncategorized" means "has no active category," not "has no category row"

The scope is:

```ruby
Bill
  .joins(:bill_llm_provisioning)
  .where.not(bill_llm_provisionings: {llm_summary: nil})
  .where.not(id: BillCategory.joins(:category).where(categories: {active: true}).select(:bill_id))
  .where(
    "bill_llm_provisionings.generation_status IS NULL OR bill_llm_provisionings.generation_status != ?",
    "failed"
  )
```

A bill whose only category is `active: false` re-opens for
re-categorization. That is why the exclusion joins through `Category` and
filters on `active: true`, instead of the simpler
`.where.not(id: BillCategory.select(:bill_id))` — the simpler form would
skip such a bill, because it still carries a `BillCategory` row even though
none of its categories count.

Rows whose summarize step genuinely failed are excluded by the
`generation_status != "failed"` clause, so a bill whose summary call died
does not also draw a categorize call here.

## The taxonomy-mismatch case no longer marks a bill "failed"

That `failed`-status filter used to also catch bills where the summarize
call's freeform `categories` key named nothing in the active taxonomy.
`GenerateBillSummaryJob` no longer marks that row `failed`: when the
freeform response can't be matched, the bill now completes uncategorized,
because marking it `failed` stranded a paid-for `llm_summary` behind a UI
branch that never renders it.

Such bills reach the backfill scope on purpose. The backfill sends
`BillCategoryPromptBuilder`, which lists the active taxonomy and constrains
the response with `BILL_CATEGORIES_SCHEMA` — a materially better attempt
than the freeform call that produced the mismatch, not a repeat of it.

## Stamping a deterministic no-match

A later fix closed the remaining leak: a bill the *constrained* prompt also
cannot match now gets `categories_unmatched_at` stamped
(`mark_categories_unmatched!`) and is excluded from the scope by this
clause:

```ruby
.where(
  "bill_llm_provisionings.categories_unmatched_at IS NULL OR " \
  "bill_llm_provisionings.categories_unmatched_at < bill_llm_provisionings.llm_generated_at"
)
```

That keeps "zero LLM budget on later boots" true without exception —
without the stamp, a bill the constrained prompt still can't categorize
would draw a fresh, billed call every single boot forever.

The stamp is cleared automatically in one case: when the active taxonomy
changes (`Admin::CategoriesController`), because the reason the bill
couldn't match may have gone away. No separate operator action re-arms the
bill.

The stamp is also implicitly cleared by rewriting the summary, without any
code touching the stamp itself. `categories_unmatched_at` is a verdict
about one specific piece of text — the summary the constrained prompt read
at that moment. `llm_generated_at` records the age of the *current*
summary text; both places that write the summary set it in the same
statement as the text, and the settle path deliberately doesn't write it on
a run that bought nothing. Comparing `categories_unmatched_at` against
`llm_generated_at`, rather than against `NULL`, therefore means a stamp older than
the summary it was about has been outlived by that summary — a
regeneration or an operator paste re-arms the bill on its own.

A stamped row with no `llm_generated_at` keeps its stamp: the comparison
against `NULL` is never true, so the row stays excluded. Those rows predate
the `llm_generated_at` column, their summary has no known age, and
re-arming them every boot would just buy the same no-match answer forever.

`NULL` and other statuses (old summarized rows that predate
`generation_status`) stay in the set — only an explicit `"failed"` status
excludes a row.

## Concurrency: the fixed proc key

`limits_concurrency to: 1` with a proc key collapses concurrent enqueues
from puma and `bin/jobs` into one run. The remaining join-row race is
contained by the per-bill rescue block (below). Only one copy of this job
may run at a time; the proc key follows the same
`->(*_args, **_kwargs) { "..." }` form used in
`run_legislation_pipeline_job.rb`. `perform` takes no arguments, so a fixed
key is right here — unlike `legislator_vote_fetch_job.rb`, which keys per
`bill_id`.

## Why the empty-active-taxonomy bail happens before the adapter is built

With zero active categories every summarized bill counts as uncategorized,
so without a guard the job would make one real, billed Claude call per
bill — each dying with `Llm::SchemaError` (no valid categories) — and
repeat that every boot. This mirrors the same empty-active-set skip in
`GenerateBillSummaryJob`. The active taxonomy is loaded ONCE and reused
across `find_each` (no per-bill query), and `.order(:name)` keeps the
prompt order stable, so the Anthropic prompt-cache key stays the same
across boots.

## Why the `Llm::SchemaError` rescue wraps only the assigner

The rescue around `BillCategoryAssigner.new(...).call` wraps ONLY the
assigner, not the whole iteration, and that scoping is the whole point.
`Llm::SchemaError` has two very different sources: `BillCategoryAssigner`
raises it when the model answered and NO name matched the active set — a
deterministic outcome that repeating the call cannot change — while
`LlamacppAdapter` raises the same class for a malformed response, which is
transient and SHOULD be retried next boot. Catching it around the whole
body would permanently exclude bills over a passing network-shaped
failure. Only the deterministic no-match gets the stamp.

## Why the per-bill rescue is broad, and what that trades away

One bad bill must NEVER abort the whole backfill batch, so the outer
rescue catches `StandardError` broadly, logs, and continues.
(`GenerateBillSummaryJob` also catches `StandardError` broadly but
RE-RAISES so ActiveJob can retry it — same pattern, different action. A
boot-time batch cannot re-raise: that would drop every remaining bill this
run, so here it swallows per-bill and moves on.)

Narrowing to specific classes would let the COMMON concurrent-race outcome
escape: `BillCategory` has `validates :bill_id, uniqueness: {scope:
category_id}`, whose validation SELECT runs AFTER `find_or_create_by!`'s
find, so a row a concurrent `GenerateBillSummaryJob` commits in between
surfaces as `ActiveRecord::RecordInvalid` (from the validator), NOT the
DB-index `ActiveRecord::RecordNotUnique` — and `RecordInvalid` would escape
`find_each`, silently dropping every remaining uncategorized bill this
boot.

Trade-off: a genuine programming error (`NoMethodError` etc.) is likewise
logged per-bill rather than crashing the boot, but stays visible via the
logged exception + `bill_id` (and would recur identically on the next
boot).

## Why the unmatched-stamp log is at `warn`, not silent

`mark_categories_unmatched!` logs at warn rather than swallowing the
outcome silently — an operator seeing this repeatedly is being told their
taxonomy has a gap.
