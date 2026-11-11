---
lat:
  mode: explanation
---

# Summary call preconditions and citation validation

Explains the bill-summary call's own precondition check, separate from the positions call, and the shared citation validation logic both writers use.

## The summary call has its own precondition

The summary call in `GenerateBillSummaryJob#perform` carries its own precondition, independent of the positions call's.

The two calls read completely different inputs: the summary call reads the on-disk diff markdown or `bill.extracted_text` (NOT `diff_content`, which is an artifact mirror the prompt never renders), while the positions call reads testimony and, by design, none of those, which means one shared gate could only ever be right for one of them.

It used to be wrong: `GenerateBillSummaryService` guarded BOTH calls on `source_present?`, which locked a testimony-only bill (bill PDF missing or its extraction failed, hearing attachments fine) out of positions entirely. That guard is now "does EITHER call have its inputs," and the summary call's own `builder.source_present?` check in `#perform` is the other half — without it, letting a testimony-only bill through the service would mean paying for a summary of nothing, i.e. fixing a budget bug by opening a new way to burn budget.

`RunLegislationPipelineJob#execute_bill_level_service`'s inline `perform_now` bypasses the service guard entirely, so this in-job gate is also the only source precondition that code path has ever had.

`parsed` (the summary response) stays `nil` on the skip, which is what the citation and category logic below keys on: no response means no verdict to record and nothing to categorize from, and neither may be fabricated from its absence.

`parsed` also stays `nil` on a positions-only resume, for the same reason and to the same effect: the summary on this row was bought by an earlier execution of this same enqueue and is already committed, so there is no response to record a verdict from and no body to write again. (See [[docs/explanation/bill-summary-re-entry-guard.md|bill-summary-re-entry-guard.md]].)

## Citation validation

When a summary response comes back, `#perform` checks the summary's `cited_section_keys` against the bill's parsed `BillSectionReference` records — the ground truth for which sections actually exist.

The check goes through `SummaryCitationValidator.verdict_attrs`, the single entry point shared with `PasteSummaryService` — the other writer of the `citations_valid` and related columns.

### The bug this shared helper fixed

The two writers used to give OPPOSITE answers for a payload that omits `cited_section_keys`.

This job's call site passed `nil` straight to the validator, which reported an empty `invalid_citations` list, so `valid?` was true and the row asserted `citations_valid: true` for a body nothing had checked. `PasteSummaryService` wrote `nil` for the same input, and its own comment named this direction as the dangerous one — correctly: the column is exposed on `to_builder`, so a rule like "publish only summaries with verified citations" would have read the fabricated `true` as verification.

Both writers now share one helper precisely so they cannot drift again — two hand-copied versions of the same decision is what produced the divergence, and each had a green spec pinning its own half of the contradiction.

### When the check runs

This runs only when a summary was actually bought.

A skipped call leaves `citations_valid` untouched rather than writing a verdict about a body that does not exist — the same "not validated is not the same as clean" rule `verdict_attrs` enforces for an absent `cited_section_keys`, one level up.

## Building the prompt: ordering and call-shape gotchas

The active category list is loaded BEFORE the summary prompt is built, so the prompt can list the available categories.

Without this the model returns no `categories` key and every new summarize fails at category assignment. `.order(:name)` keeps the prompt order deterministic so the Anthropic prompt-cache key stays stable across summarize calls.

`BillSummaryPromptBuilder.new(bill, active_categories:)` takes `active_categories` as a keyword argument with a default. A positional 2-arg call raises `ArgumentError` (given 2, expected 1) and crashes every summarize.

Positions are recorded from the value actually sent to the API. Positions no longer come from the summary call — `draft_org_positions` was dropped from the summary output contract; see the testimony-gated positions call in [[docs/explanation/bill-summary-positions-evidence-digest.md|bill-summary-positions-evidence-digest.md]] instead.

## Why GenerateBillSummaryService.call gates on runnable?, not just source material

`GenerateBillSummaryService#call` gates on whether the job has ANYTHING to do, which is not the same question as "is there source material?".

`GenerateBillSummaryService#call` gates on whether the job has ANYTHING to do, which is not the same question as "is there source material?" — `#runnable?` is also true when the operator supplied testimony with no source text at all, so a bill with only a pasted paste can still run the positions half.

## Why generate_bill_summary_job_spec.rb's default fixture sets bill.extracted_text, not just :with_diff_content

Every "the summary call fires" example in this spec depends on `source_present?` being true, and that check reads `#source_text_section`, which renders the on-disk diff markdown or `bill.extracted_text`.

Every "the summary call fires" example in this spec depends on `source_present?` being true, and that check reads `#source_text_section`, which renders the on-disk diff markdown or `bill.extracted_text` — never `bill_llm_provisioning.diff_content`.

The fixture used to rely on `:with_diff_content` alone, on the strength of a comment calling `diff_content` "one of the three signals `source_present?` reads." It was one — and that was the defect: `#source_text_section` never rendered that column, so every "the summary call fires" example in this file was sending a prompt whose bill-content section read "No bill text is available yet." The adapter is stubbed in every example, so nothing noticed, and the file stayed green over a paid call for a prompt with no bill text in it.

The default `let(:bill)` now sets `extracted_text:` directly. `:with_diff_content` stays on the default `provisioning`, because several examples check `diff_generated_at` and what that column means for artifact presence — it just no longer doubles as the signal that source text exists. The two groups that want NO source text (the testimony-only group, and the group where neither call has its inputs) clear `extracted_text` themselves.

`spec/system/admin_llm_summary_spec.rb`'s default `let(:bill)` sets `extracted_text:` for the same reason: its fixture used to get past the check with `:with_diff_content` alone, paying for end-to-end summarize calls whose bill-content section also read "No bill text is available yet."

Both "already running" contexts in `bills_spec.rb`'s idempotency group need a bill with real source text for the same reason: the service checks `runnable?` BEFORE the "already running" check, so a bill with no source stops at `:no_pipeline_data` and a "does not enqueue another job" assertion would pass without the already-running check ever running — a green example measuring nothing.

`spec/requests/bills_spec.rb`'s `summarizable_bill` fixture and `spec/requests/bills_regenerate_summary_spec.rb`'s stale-chip acceptance group set `extracted_text:` for the same reason. The plain `bill` fixture in `bills_spec.rb` deliberately has no source text, so the "no pipeline data" contexts keep testing that refusal, while the contexts that expect a job to be enqueued point at `summarizable_bill` instead. `bills_regenerate_summary_spec.rb`'s fixture keeps `diff_content` as well as `extracted_text`, because `#stale?` reads `diff_generated_at` and that group is specifically the stale-chip acceptance test — `diff_content` no longer doubles as the source-text signal, but it is still needed for that separate check.

## Why the no-pipeline-data state checks for a missing provisioning row, not empty diff_content

`BillCreatorLlmSummary` shows the no-pipeline-data state only when the `bill_llm_provisioning` row is missing altogether — the check is `!provisioning`, not `!provisioning.diff_content`.

The second version used to wrongly hide the completed state for bills that amend nothing, whose `diff_content` is legitimately empty. The system spec covering this state creates no provisioning row at all, rather than one with blank `diff_content`, so it cannot pass for the wrong reason.
