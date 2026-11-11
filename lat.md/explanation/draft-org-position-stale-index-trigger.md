---
lat:
  mode: explanation
---

# Why reject and edit needed a draft identity check

Rejecting and editing a draft have to name which draft they mean, not just its position in the list.

Approving already worked that way: `ApproveOrgPositionService` takes a `draft_org_name`, so an out-of-date position number cannot approve a different draft by mistake. `BillDraftOrgPositionsController#update` changes the list the same way — it calls `drafts.delete_at(index)` to reject and `drafts[index] = entry` to edit — and had no such check.

## The trigger: one person, two cards, one reload

One person alone can trigger this.

Each card disables only its own button while it submits (`BillCreatorOrgPositionCard`), so after Reject on the first card the server deletes position 0 and redirects, but the page reload that follows is not instant. The second card is still on screen holding the position it had before the delete, and a click on its Reject arrives carrying that stale number.

See [[docs/explanation/draft-org-position-identity.md|Identifying one entry in draft_org_positions]] for how `draft_token`/`draft_org_name` fix this once a caller has to name a draft, and [[docs/explanation/org-position-draft-identity-exemption.md|Draft identity and the approval exemption]] for the equivalent rule on the approve path.

## Why the identity guard spec needs more than one draft per bill

Every example in `spec/requests/bill_draft_org_positions_identity_spec.rb` starts with more than one draft on purpose.

`bill_draft_org_positions_idempotency_spec.rb` uses single-item lists throughout, which is exactly why it could not catch this bug: with fewer than two survivors, a stale position falls off the end of the list and gets the harmless "Draft already removed." answer instead of destroying a real draft.
