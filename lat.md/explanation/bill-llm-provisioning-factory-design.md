---
lat:
  mode: explanation
---

# bill_llm_provisioning factory design

`spec/factories/bill_llm_provisionings.rb` (`FactoryBot.define`, factory `:bill_llm_provisioning`) has several traits whose scope is easy to get wrong by analogy with what they sound like they should do.

## :with_diff_content does not mean "there is source text to summarize"

This trait does NOT make `BillSummaryPromptBuilder#source_present?` true, so never use it to mean "this bill can be summarized".

`diff_content` is the JSON copy of the artifact that `GenerateDiffsService` writes for `Pipeline::ArtifactPresence`, and `#source_text_section` has never rendered it. For "there is source text to summarize", set `extracted_text` on the BILL, or write a diffs markdown file — those are what the prompt really carries. See [[docs/explanation/bill-summary-call-preconditions.md|Summary call preconditions and citation validation]] for what the summary call's own precondition actually reads.

## :with_testimony and why :with_drafts pulls it in automatically

`draft_org_positions` only ever exist because testimony existed first.

The LLM call that writes positions runs only when `BillLlmProvisioning#testimony_present?` is true (the `positions_attempted` path in `GenerateBillSummaryJob`), `PasteSummaryService` applies the same condition, and `ApproveOrgPositionService` closes the last door by refusing a draft on a bill that has no testimony. So a fixture pairing drafts with two empty testimony columns describes a state the pipeline cannot reach.

`:with_testimony` sets `extracted_testimony` for examples that are about approval mechanics rather than about the gate itself.

`:with_drafts` pulls in `:with_testimony` itself rather than leaving that to the caller, because no fixture may pair a draft with no evidence. That pairing means something else — testimony was retracted, see [[docs/explanation/evidence-retraction.md|Marking a draft's evidence as retracted]] — and fixtures spell that out on purpose rather than getting there by omission.

Each `draft_org_positions` entry `:with_drafts` builds has the shape `config/schemas/bill_positions.json` validates and `GenerateBillSummaryJob` saves. `bill_llm_provisioning_spec.rb` checks it against that schema, so this fixture cannot drift away from the real thing.

## :completed seeds only the summary, on purpose

`:completed` seeds the SUMMARY as finished, and nothing else.

It used to seed a `draft_org_positions` entry as well, so every fixture that only meant "the summary finished" was also claiming an organization had taken a position on the bill — with both testimony columns nil, which is exactly the state `:with_testimony` above says the pipeline cannot produce. Drafts now live in `:with_drafts`, which brings their evidence along.

## Why the request spec asks the controller for the prop, not the fixture

`spec/requests/bills_spec.rb`'s "serves the `bill_llm_provisioning` row on the bill prop" example used to make no request at all.

`spec/requests/bills_spec.rb`'s "serves the `bill_llm_provisioning` row on the bill prop" example used to make no request at all: it created a provisioning row, reloaded it, and read the factory's own attributes back off the model. That passed even while `BillsController#bill_creator_props` had `b[:bill_llm_provisioning]` hard-wired to nil — the one prop the example claims to cover. It now asks the controller for the prop instead of asking the fixture about the fixture.

## :skipped

The end state a summary job leaves behind when it is skipped for being out of date. See [[docs/explanation/bill-llm-run-reclaim-timing.md|bill-llm-run-reclaim-timing.md]] for the staleness rules that produce this state.
