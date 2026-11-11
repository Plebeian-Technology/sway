---
lat:
  mode: explanation
---

# Detecting an unreviewed AI summary

`Bill#summary_ai_unreviewed?` is true when the published `summary` is still exactly the model's own words, with nobody having revised it. The bill page shows a notice when this is true.

## The test

The method compares the live `summary` column against `bill_llm_provisionings.llm_summary`, the stored draft.

Publishing copies the draft's text into `summary`. If a person later edits that text, the two values stop matching, and the method returns false.

## Why not updated_at

`updated_at` cannot make this distinction. It moves both when a machine publishes the summary and when a person edits it afterward, so a comparison against it cannot tell which one happened.

## Pasted summaries are not machine words

A summary an operator pastes in through `PasteSummaryService` is not AI-generated text, even though it also lands in `llm_summary`.

That service stamps `llm_provider` with `BillLlmProvisioning::OPERATOR_PASTE_PROVIDER` to record this. This codebase treats a paste as hand-written everywhere else too — the supersede gate and the regenerate warning both make the same distinction — so `summary_ai_unreviewed?` returns false for a paste even if `summary` still matches it exactly.

## Why an organization position needed its own column instead

A bill summary can compare its live `summary` column against the stored draft on `bill_llm_provisionings.llm_summary` because that draft persists.

An organization position has no such twin: its draft lives in `bill_llm_provisionings.draft_org_positions`, and approving a draft DELETES the approved entry from that array — a moment later there is nothing left to compare the published position against.

`organization_bill_positions.ai_summary` (`db/migrate/20260807120000_add_ai_summary_to_organization_bill_positions.rb`) holds the model's own words instead, so the comparison has something to compare against even after the draft is gone. `NULL` means no machine wrote this text — an admin typed the position in directly, and that row carries no notice because there is nothing machine-written about it.

The column holds the model's text rather than a reviewed flag for the same reason `summary_ai_unreviewed?` above doesn't use `updated_at`: a flag has to be cleared by every writer that changes the text, and one writer that forgets leaves a stale "reviewed" mark on text nobody actually read — the unsafe direction. Comparing content instead asks nothing of any writer: the moment the live text differs from the stored words, a person revised it, however the edit arrived.

## publish_summary!: why generation and publish share one transaction

`GenerateBillSummaryJob#publish_summary!` puts the summary a run bought on the public bill page.

It runs INSIDE `#persist_unless_superseded!`'s lock, in the same transaction as the write that persists the draft. Generating and publishing must happen together: if a run wrote a new draft while an older machine-written summary stayed published, the two would differ, and `summary_ai_unreviewed?` above would read that as "a person revised this" — a notice coming off text nobody read. One transaction means no moment exists where that is true. A failure to publish therefore rolls the draft back with it, which is the right way round: a draft with no publish is the state that makes the notice lie.

Only the summary persist reaches the decision — the positions persist passes no `:llm_summary`, so `#publish_summary!` returns at once. Organization positions carry their own notice, off `organization_bill_positions.ai_summary`, written where a draft is approved.

`BillSummaryPublication` owns the refusal: a summary a person wrote is never published over. The refusal sends no signal back to the caller — the draft is on the row either way, and the published text stays the person's.

The write itself uses `update_columns`, not `update!`. It runs inside the lock that just committed a summary somebody paid for; a validation failure on an unrelated column would raise here and roll that purchase back — a seeded bill with a missing required field does exactly that. Nothing on `Bill` watches `summary`: neither `VOTE_TRIGGER_FIELDS` nor `SCORE_TRIGGER_FIELDS` lists it, so this skips no callback that would otherwise run. `updated_at` is set by hand, because `update_columns` does not touch it, and a row that changed must say it changed — though nothing reads that timestamp to decide whether a person reviewed the text; see above for what does.

`#persist_unless_superseded!` reads `provisioning.llm_summary` into `previous_draft` BEFORE writing the new attributes onto the row — that read is the only copy of the outgoing draft's text, and `#publish_summary!` needs it to tell an earlier publish apart from a person's own words when it calls `BillSummaryPublication.publishable?`.
