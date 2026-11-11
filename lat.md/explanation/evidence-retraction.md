---
lat:
  mode: explanation
---

# Marking a draft's evidence as retracted

`BillLlmProvisioning.drafts_with_evidence_retracted` marks non-news drafts when committee testimony is withdrawn. News-sourced positions are retracted via `BillLlmProvisioning.drafts_with_news_evidence_retracted` when article evidence changes.

The full catalog of what triggers the mark lives in [[docs/reference/evidence-retraction-writers.md|Who marks a draft's evidence retracted]]; this document covers the rule itself and the reasoning behind it.

## The rule

Writers stamp when a write establishes, for certain, that the evidence these drafts were built from has disappeared. Writers do not stamp when the evidence merely might be gone, and do not stamp when an operator is undoing an administrative action.

This is the invariant every writer of the mark shares. An earlier version of this rule claimed there was only one such writer — there are multiple writers across hearing and news ingestion pipelines.

Every comparison a writer makes is correct only while the [[docs/explanation/testimony-mirror-rule.md|testimony mirror rule]] holds: the stored `testimony_attachments` mirror describes the stored `extracted_testimony` composition.

## Selective retraction between testimony and news evidence

Draft positions originate from legislative hearing testimony or approved news reporting articles, so retraction operates selectively between the two independent evidence streams.

Hearing testimony updates (`FetchHearingsService`, `SupplementalTestimonyWrite`) only stamp non-news-sourced drafts via `BillLlmProvisioning.drafts_with_evidence_retracted`. News-sourced positions remain unretracted because committee hearing alterations do not invalidate published journalistic reporting.

News article updates (`ReviewBillNewsArticleService`) stamp only drafts matching the specified article ID and stale text version ID via `BillLlmProvisioning.drafts_with_news_evidence_retracted`. Hearing testimony drafts and drafts from other approved news articles remain untouched.

## This is not a delete

`draft_org_positions` is triage work an operator can edit — the same reasoning that keeps it intact when a positions run fails — so retraction marks the drafts and refuses them rather than throwing the work away.

The mark goes away when a positions call succeeds and replaces the whole array (`GenerateBillSummaryJob`), or when the operator rejects the draft.

## Why the first timestamp wins

Stamping twice keeps the FIRST timestamp, which is the earlier and therefore truthful answer to "when did this evidence go away".

Re-stamping on every later fetch-hearings run or article review would date the withdrawal to whenever an operator last refreshed the screen.

## What is left untouched

Elements that are not Hashes pass through untouched — the old `{"rejected" => true}` stub, and anything else this operator-editable JSON column can hold. They are not drafts anyone can act on, and they have nowhere to carry a key.

## Reading the mark

`BillLlmProvisioning.draft_evidence_retracted?(entry)` is true when THIS one entry's evidence was withdrawn — the reading side of the mark.

`ApproveOrgPositionService` uses it in both of its checks, the quick one before the database transaction and the deciding one inside the lock, so the two can never disagree about refusing. For news-sourced positions, `NewsOrgPositionGroundingService.entry_still_grounded?` provides approval-time verification that the underlying article remains approved with matching text version content.

## The frontend's IOrgPosition.evidence_retracted_at

A timestamp (ISO-8601) marking this draft's evidence as withdrawn — the authoritative sign `ApproveOrgPositionService` refuses to approve on.
