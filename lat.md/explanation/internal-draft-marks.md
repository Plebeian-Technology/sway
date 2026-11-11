---
lat:
  mode: explanation
---

# Internal marks on a draft org position

`draft_org_positions` entries can carry two internal marks — facts the code itself records, not something the model or an operator said.

This document covers both marks, why each is a key inside the JSON rather than a database column, and how a wholesale paste-replace preserves them.

## DRAFT_EVIDENCE_RETRACTED_KEY

The key stored on a single draft to record "the testimony these conclusions were drawn from has been withdrawn". See [[docs/explanation/evidence-retraction.md|Marking a draft's evidence as retracted]] for the rule that decides when it gets stamped.

### Why a key inside the JSON and not a database column

What gets marked is one entry of a JSON array, and everything that reads those entries works one at a time.

What gets marked is one entry of a JSON array, and everything that reads those entries works one at a time: Approve publishes ONE draft, Reject retires ONE draft, and a marked draft can sit right beside an unmarked one (pasting can add positions to a bill whose earlier drafts were already withdrawn). A column on the row could not say which drafts it covered. A key also needs no migration, which leaves the schema decision — and the question of a one-off backfill — with the operator.

### Why a timestamp and not a yes/no flag

Looking at a refused card, the operator wants to know when this stopped being true, and the timestamp points at the fetch-hearings run that took the evidence away.

### Why reject and edit are unaffected by the mark, and why edit must not erase it

Reject and edit are the two `BillDraftOrgPositionsController` actions that are not approval.

Neither publishes anything, so neither is blocked when a draft carries `DRAFT_EVIDENCE_RETRACTED_KEY` — but an edit must not wash the mark away either. `#apply_draft_decision` merges the allowed keys into the existing entry rather than replacing it, so renaming or rewording a retracted draft leaves it retracted: retyping a summary is not new evidence. Rejecting is the actual remedy for a retracted draft.

## DRAFT_SUMMARY_EDITED_KEY

The key stored on one draft to record "a person rewrote this draft's summary".

### Why it exists

Approving a draft copies its text into the new organization position's `ai_summary` column.

That column means "the model's own words". But `BillDraftOrgPositionsController`'s edit branch merges an operator's rewrite into the stored entry. After one edit the draft's summary is a person's words. Without this mark, approving copies a person's sentence into a column named for the model's, and the bill page then tells readers a machine wrote what a person wrote. This mark removes that defect: a name that states a fact the code does not otherwise enforce.

### The rule

Stamp only when a write CHANGES the summary text.

A rename of the organization leaves the model's sentence alone, and a stance correction does too. Neither is a revision of the sentence. An existing mark stays: it records when the text stopped being the model's, and a second edit does not move that moment.

`DRAFT_EVIDENCE_RETRACTED_KEY` above is a key inside the JSON, not a column, for the same reason: what gets marked is one entry of an array, an edited draft sits beside unedited ones, and a column on the row cannot say which drafts it covers. It is a timestamp rather than a yes/no flag for the same reason too — an operator who looks at a draft wants to know when it stopped being the model's text.

### Reading the mark

`BillLlmProvisioning.draft_summary_edited?(entry)` is true when a person rewrote THIS one entry's summary — the reading side of the mark.

`ApproveOrgPositionService` reads it to decide whether the text it publishes is the model's own words.

## INTERNAL_DRAFT_MARKS

Every key this class stamps onto one `draft_org_positions` entry to record an internal fact, rather than something the model or an operator said.

It currently holds `DRAFT_EVIDENCE_RETRACTED_KEY` and `DRAFT_SUMMARY_EDITED_KEY`. `draft_org_positions_preserving_marks` (below) reads this list so a wholesale paste-replace ignores ALL of them when deciding two entries describe the same draft, and carries forward every one it finds — not only the mark it was first written for. A future third mark needs one line added here; nothing else has to change.

## Carrying marks through a paste

`BillLlmProvisioning.draft_org_positions_preserving_marks(stored, pasted)` carries a mark forward from `stored` onto `pasted`, for every pasted entry whose other fields exactly match a marked stored entry.

### Why this is needed

`PasteSummaryService` writes `pasted` as a wholesale replacement of the column — the same shape of write `GenerateBillSummaryJob`'s positions persist makes (see the whole-write note in [[docs/explanation/evidence-retraction.md|Marking a draft's evidence as retracted]]).

That job guards its replacement with an evidence digest so it can decline to overwrite a mark still describing evidence that is genuinely gone. A paste has nothing to compare a digest against: an operator's JSON never carries this key, because it is an internal fact about a withdrawal, not something the text they pasted from could know. As a result the ordinary sequence — paste the same generated JSON back in, unaware a hearings fetch retracted one of its entries in the meantime — would otherwise erase the mark just by replacing the array with a byte-for-byte copy of what was already stored.

### The match is content, not position

An entry counts as "the same draft" only when every field but the marks themselves is identical.

This is NOT the rule `.draft_token` uses (see [[docs/explanation/draft-org-position-identity.md|Identifying one entry in draft_org_positions]]): that method hashes the WHOLE entry, marks included, because its job is to tell two array elements apart. This method's job is different — decide whether a mark still describes a pasted entry — so it must ignore the marks on purpose, or a marked entry could never match the unmarked pasted JSON it is being matched against. A pasted entry that changed `org_name`, `stance` or `summary` is a new claim, and it gets no inherited mark: the operator asserted something a retraction never applied to, and whether IT rests on real evidence is a question for the next positions run, not this write.

### Every mark, not only the retraction

`draft_org_positions` carries two internal marks (`INTERNAL_DRAFT_MARKS`), and a pasted entry can carry neither in its own JSON — both are internal facts an operator's source text cannot know.

Matching on a key that excludes only one mark left the other one (`DRAFT_SUMMARY_EDITED_KEY`) INSIDE the comparison. The schema forbids extra properties on a pasted entry, so a stored entry carrying that mark could never match a pasted entry again — every match failed, and paste silently destroyed both marks on exactly the entries that had been edited. Matching on content that excludes every mark, and carrying every mark that was present back, is what a "wholesale replace that does not know about internal marks" needs.
