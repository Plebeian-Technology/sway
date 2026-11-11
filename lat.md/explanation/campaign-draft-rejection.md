---
lat:
  mode: explanation
---

# About rejecting a campaign draft

Why rejecting a campaign draft is stored against the bill by content hash, and why a rejected card stays on screen instead of disappearing.

## The problem: a campaign draft has no row

{#campaign-draft-rejection} {#stored-decision}

A campaign draft is derived data. The Bill Creator reads it out of the cleaned-testimony artifact's `groups` array on every request, so it has no database row and no primary key of its own. Reject was therefore a client-only `setDismissed(true)`: the operator's decision lived in React state and was gone on the next page load, and gone again after every re-run of the clean-testimony stage.

The decision is now stored on `bill_llm_provisionings` in a JSON array column, `rejected_campaign_draft_hashes`, beside the `draft_org_positions` column that already solves the same problem for organization drafts.

## Why the key is a content hash

{#identity-is-the-hash}

The stored key is the pair (bill, campaign-draft content hash). The hash is the draft's own stable id — a SHA-256 digest of the reused text, written by the grouping stage — so it survives a re-run that reorders unchanged drafts. An array index does not: a re-run that adds or drops one group renumbers every draft after it, which would silently move a rejection from one campaign to another. A database id is not available at all, because there is no row.

The column lives on the provisioning row rather than in the artifact, so a re-run of the clean-testimony stage rewrites `cleaned_testimony` without touching the decision.

## Why a rejected card stays visible

{#restore}

A rejected draft renders as a one-line REJECTED record with its own Restore button rather than vanishing from the list. A decision an operator cannot see is one they cannot undo, and on a civic transparency platform an operator must be able to review what was excluded from a bill's record and put it back.

The card reads `rejected` straight off the server prop, so a rejected draft paints as rejected on first render — there is no client round-trip in which it briefly appears approvable.

## The activity log

{#activity-log}

Reject, mark-individual, and restore each write an `org_position_decision` entry through `PipelineActivityLogger`, with the draft named by `<bill_id>-campaign-<hash>`, the same identity shape `ApproveCampaignPositionService` logs. Only a decision that actually changed the stored list is logged, so a double-click does not produce two entries.

## Releasing drafts to individual letters

{#individual-letters}

Operators can mark a false-positive campaign draft as individual constituent letters rather than rejecting or approving it.

The decision stores the content hash in `bill_llm_provisionings.individual_campaign_draft_hashes`. Marking a draft as individual removes its hash from `rejected_campaign_draft_hashes`, and rejecting a draft removes it from `individual_campaign_draft_hashes`. This mutual exclusivity prevents a draft from being simultaneously excluded and exposed in public constituent testimony. Restoring a draft clears both lists.

The column stores an array of SHA-256 strings matching the campaign grouping digest. Array serialization ensures that reordering of campaign drafts across pipeline runs does not scramble operator decisions, while `mark_campaign_draft_individual!` deduplicates hashes and rejects blank values before database persistence.

Because clean-testimony artifact re-runs overwrite transient letter groups but leave provisioning rows intact, persisted hashes preserve operator overrides across re-generations. Constituent letter extraction reads these hashes to admit letters from marked drafts while excluding letters from rejected or unreviewed campaigns.

The `POST /bills/:bill_id/campaigns/mark_individual_draft` endpoint on `CampaignsController` applies this decision through `provisioning.mark_campaign_draft_individual!`, logs the decision via `PipelineActivityLogger`, and redirects back to the summary bill creator with a flash notice. `TestimonyCampaignDraftResource` serializes the `marked_individual` attribute by checking draft inclusion in `params[:individual_hashes]`, exposing the state to the Bill Creator surface.
