---
lat:
  mode: explanation
---

# Attributing an approved summary to a model or a person

`OrganizationBillPosition#ai_summary` means "the model's own words." Whether `ApproveOrgPositionService` writes text into it, or writes `nil`, decides whether the bill page tells a reader a machine wrote this sentence.

## ai_summary is written on every approval, nil included

`#upsert_position` uses `find_or_initialize` plus `save!`, so stance and summary edits apply on both the create path and a re-approval after operator edits.

Writing `ai_summary` on every approval — including writing `nil` — is what keeps the column honest on a RE-approval: take a position first published from a model draft, then re-approved from a person's own words. It has to stop claiming the model wrote it. Leaving the old value in place would do the opposite.

## approved_ai_summary: three ways the answer is nil

`#approved_ai_summary` answers one question: did a machine write the sentence being published? Three situations answer no, and each has its own check:

| Situation | Why it answers no |
|---|---|
| No draft named | A caller with no `:index` asserts a position from its own inputs. It doesn't promote one the pipeline drew from testimony, so nothing machine-written is involved. |
| The draft was edited (via the controller) | `BillDraftOrgPositionsController`'s edit branch merges an operator's rewrite into the stored entry. The draft's summary is a person's words by then. That edit stamps `DRAFT_SUMMARY_EDITED_KEY` (see [[internal-draft-marks]]), so `#approved_ai_summary` can tell the two apart. |
| The operator changed it here (via the card) | The card lets an operator rewrite the sentence in the browser and send the new one straight to Approve. The stored draft is untouched. Comparing what arrived against what's stored catches this case — it needs no mark. |

`#approved_ai_summary` returns the STORED draft's summary, never `@summary` (what arrived in the request). On an ordinary approval the two are the same string. When they differ, the operator revised the text. Returning the stored text either way would make `OrganizationBillPosition#summary_ai_unreviewed?` read `false` regardless; returning `nil` says why the text isn't the model's, and keeps the column meaning one thing.

It reads the pre-transaction array on purpose. This method runs before `#delete_approved_draft`, which removes the entry; the identity re-check inside that method proves the entry is the one the caller named. (See [[docs/explanation/draft-org-position-identity.md|Identifying one entry in draft_org_positions]] for how an entry's identity is established.)
