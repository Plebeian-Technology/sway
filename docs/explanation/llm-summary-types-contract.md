---
mode: explanation
summary: "Explains several IBillLlmProvisioning/IOrgPosition/IBillPipelineLastFailure type-contract decisions: why the old positions vocabulary cannot resurface, why generation_status='skipped' is not a failure, why llm_provider had to be declared explicitly, and why IBillPipelineLastFailure carries no member count."
status: agent-extracted
related: [docs/explanation/draft-org-position-identity.md, docs/explanation/evidence-retraction.md]
---
<!-- vale Vale.Spelling = NO -->

# Type-contract decisions in llm-summary/types.ts

## Why `IOrgPosition` cannot fall back to the old vocabulary

The shape this data arrives in, defined by `config/schemas/bill_positions.json`
and written by `GenerateBillSummaryJob`. The older vocabulary — a `support`
key and a `confidence` score — is retired as of this file.

Could a row saved earlier still carry that old vocabulary, and so render a
blank badge or refuse to be approved? It cannot, for four separate
reasons, which is why nothing here falls back to the old shape:

1. No `bill_llm_provisionings` row has `draft_org_positions` that mention
   "confidence", a "support" key, or a stance in capitals; any entry saved is
   already `{org_name, stance, summary}`.
2. `support` was never saved to the database at all. The old shape was
   `{org_name, stance: "FOR", confidence, summary}`, as an earlier version
   of `spec/factories/bill_llm_provisionings.rb` shows. `support` existed
   only as a claim made by the frontend's old `IOrgPosition` type, which is
   why the code reading it was itself wrong.
3. Every writer is checked against a schema first: `bill_summary.json` (the
   paste path) and `bill_positions.json` (the LLM job) both forbid unknown
   keys and require `stance` to be `support`, `oppose`, or `neutral`.
4. `BillDraftOrgPositionsController#edit_params` accepts only `:org_name`,
   `:stance` and `:summary`, so an edit cannot bring the old keys back.

## `generation_status`: `skipped` means superseded, not broken

`skipped` means an out-of-date summary job was cleared out of the backlog
without running. The row is finished but can be started again: it was
superseded, not broken.

## `stale`

True when the summary is out of date. The server works this out on its
own: the bill diff or the testimony was fetched more recently than the
summary was generated. Nothing else feeds into it, and the browser only
reads the boolean.

## `stale_change_kind` / `stale_change_at`

WHICH change overtook the summary, and WHEN. Both come from the single
answer `stale` itself comes from (`BillLlmProvisioning#stale_change`), so
the marker cannot appear and then name a cause the flag did not come from.

Null on a row that is not out of date. See `staleChange.ts` for why the
server decides this rather than sending the two raw timestamps.

## `llm_provider`: dropped at the type boundary

Where the summary text came from. The server has always sent this field,
but this interface never declared it, so the value was dropped at the type
boundary — searching the frontend for "operator_paste" found nothing at
all, while a comment on `GenerateBillSummaryJob` claimed the Bill Creator
rendered such bodies. It did not, and could not.

"operator_paste" means a person wrote the body by hand, and it cannot be
recovered once anything overwrites it. Any other value names the LLM
provider that produced it. Null when the row has never produced a body.

## `has_testimony`

Worked out on the server: true when there is either extracted testimony or
supplemental testimony. The extracted testimony text itself is
deliberately never sent to the browser.

## Why `IBillPipelineLastFailure` carries no member count

What the summary tab's failure alert needs about the last failed run.

No count. It said "the two fields" and gained `run_id` in the same commit
that corrected the count in its Ruby and RBS twins, `bills_controller.rb`
and `sig/controllers/bills_controller.rbs`, and missed this one. The
members are listed below, so a number here says nothing the code does
not, and saying it in a third place is only somewhere else for it to go
stale.

This sentence said "three lines down" until it was noticed that the line
it pointed at was the interface declaration, not a member. A position is a
count, it goes stale on any edit above it, and it was carried by the very
sentence arguing against keeping one.
