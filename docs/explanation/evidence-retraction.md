---
mode: explanation
summary: "Explains the rule for marking a draft org position's evidence as retracted when the testimony it was drawn from is confirmed gone."
status: agent-extracted
related: []
---

<!-- vale Vale.Spelling = NO -->

# Marking a draft's evidence as retracted

`BillLlmProvisioning.drafts_with_evidence_retracted(raw, at:)` returns `raw`
with a mark added to every Hash element, recording that the testimony a
draft's conclusions were drawn from has been withdrawn. The full catalog of
what triggers the mark lives in
[Who marks a draft's evidence retracted](../reference/evidence-retraction-writers.md);
this document covers the rule itself and the reasoning behind it.

## The rule

Stamp when a write establishes, for certain, that the evidence these drafts
were built from is GONE. Do not stamp when the evidence merely might be
gone, and do not stamp when an operator is undoing something.

This is the one thing every writer of the mark has in common. An earlier
version of this rule claimed there was only one such writer —
there are five; see the reference doc.

Every comparison a writer makes is correct only while the
[testimony mirror rule](testimony-mirror-rule.md) holds: the stored
`testimony_attachments` mirror describes the stored `extracted_testimony`
composition.

## This is not a delete

`draft_org_positions` is triage work an operator can edit — the same
reasoning that keeps it intact when a positions run fails — so retraction
marks the drafts and refuses them rather than throwing the work away. The
mark goes away when a positions call succeeds and replaces the whole array
(`GenerateBillSummaryJob`), or when the operator rejects the draft.

## Why the first timestamp wins

Stamping twice keeps the FIRST timestamp, which is the earlier and
therefore truthful answer to "when did this evidence go away". Re-stamping
on every later fetch-hearings run would date the withdrawal to whenever the
operator last happened to re-fetch.

## What is left untouched

Elements that are not Hashes pass through untouched — the old
`{"rejected" => true}` stub, and anything else this operator-editable JSON
column can hold. They are not drafts anyone can act on, and they have
nowhere to carry a key.

## Reading the mark

`BillLlmProvisioning.draft_evidence_retracted?(entry)` is true when THIS one
entry's evidence was withdrawn — the reading side of the mark.
`ApproveOrgPositionService` uses it in both of its checks, the quick one
before the database transaction and the deciding one inside the lock, so the
two can never disagree about refusing.

## The frontend's `IOrgPosition.evidence_retracted_at`

A timestamp (ISO-8601) marking this draft's testimony evidence as
withdrawn — the authoritative sign `ApproveOrgPositionService` refuses to
approve on. Five different writes can stamp it: two `FetchHearingsService`
arms, an operator's own edit or clear of the supplemental testimony field
(`SupplementalTestimonyWrite`), and a data migration — so no single cause
can be named from this column alone. Unlike `draft_token` this one IS
stored, because it is a fact about the draft rather than something
computed while building the payload. A successful regeneration clears it
by replacing the whole list.
