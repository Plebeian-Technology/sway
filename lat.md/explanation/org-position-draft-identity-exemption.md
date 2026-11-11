---
lat:
  mode: explanation
---

# Draft identity and the approval exemption

`ApproveOrgPositionService` publishes an organization's position on a bill.

Three different callers reach it, and they do not all draw on the same material — which is why one of them is genuinely exempt from the rules the other two must satisfy.

## The three caller classes

**Names a draft** (`:index`). The ordinary draft card, promoting an entry the pipeline drew from this bill's testimony. Every guard applies.

**Names a letter** (`:claimed_affiliation_position`). `BillCreatorClaimedAffiliationCard`. A claimed affiliation is not an entry in `draft_org_positions`, so there is nothing at an index to promote — but its content *is* this bill's testimony, so every bill-level guard applies to it.

**Names neither.** An admin asserting a position from their own knowledge. It draws on no testimony, so none of the testimony rules apply — including the private-individual backstop. This is the exemption, and it is deliberate. `#delete_approved_draft` destroys nothing for such a caller, and none of the evidence checks run: those rules exist for promoting a draft the pipeline drew from testimony, and this caller promotes nothing.

This document said "two exempt callers" until it was corrected. That was written when the claimed-affiliation card was indistinguishable from the admin-knowledge caller, and it described the defect rather than the design — see the next section.

## Why absence is the wrong thing to decide on

The service used to tell these apart by which parameter was missing.

Both the claimed-affiliation card and the admin-knowledge caller send no `:index`, so they were indistinguishable — and the card whose whole content is lifted from this bill's letters was read as the one drawing on none of them.

Every bill-level guard then skipped for it, including the coverage gate, while the card itself was greying out its own Approve button on two of those same rules. The screen and the server disagreed about which rules were in force.

The fix is that each caller now says what it is acting on. Identity by assertion rather than by omission is the general shape: a caller that names nothing has said something definite ("I am asserting this myself"), whereas a caller identified by a missing field is only ever *presumed* to be that, and anything else that happens to omit the field inherits the presumption.

## draft_org_name and draft_token

`draft_org_name` is the UNEDITED `org_name` of the draft the caller is acting on.

It is not the same as `org_name`: the Bill Creator card lets an operator rename a draft locally, and only sends the edited name on Approve. The unedited name exists purely to check that `:index` still points at the draft the caller meant.

`draft_token` is `BillLlmProvisioning.draft_token` of that same unedited entry (see [[docs/explanation/draft-org-position-identity.md|Identifying one entry in draft_org_positions]]), served to the card in the bill prop. When present it wins over `draft_org_name`, because a name alone does not uniquely identify a draft — two entries can share one.

## :identity_required

Sending a draft `:index` without saying which draft it should be is refused with its own outcome, `:identity_required`, rather than `:draft_index_mismatch`.

`:draft_index_mismatch` tells the caller to reload and try again, which cannot help a caller that never said which draft it meant in the first place.

## :draft_index_required

The mirror case: a caller that sends `draft_token` or `draft_org_name` but no `:index` is saying "promote THIS draft" without saying where it sits.

This gets its own outcome too, rather than `:identity_required` — that message tells the caller to send an identity, which it already did. What's missing is the position in the array.

Both checks matter for the same reason: every check further down in `#call` starts `return false if @index.blank?`. Without `:draft_index_required`, a caller that sent an identity but no `:index` would skip every evidence check and publish with nothing verified. See [[docs/explanation/org-position-approval-guard-chain.md|The approval guard chain]] for that failure mode and how it was closed.

Both outcomes are specific to THIS service. The campaign sibling, `ApproveCampaignPositionService`, retired them in favour of a single `:draft_not_found`, because a campaign draft's content hash is a stable identity that an index only weakened — see [[docs/explanation/campaign-approval-guard-chain.md|The campaign approval guard chain]]. Do not read that change as applying here: an entry in `draft_org_positions` has no equivalent stable id, so the index and the identity are both still needed.

## What each caller records in the decision log

The logged `draft_id` says which class acted and on what, so the three cannot be confused when the log is read back.

| Caller | Logged id |
|---|---|
| Names a draft | `{bill_id}-{index}` |
| Names a letter | `{bill_id}-letter-{position}` |
| Names neither | nil |

The middle row was nil until review W-20. The id was built from the `:index` that card deliberately never sends, so it could only ever be nil — which left the one approval path whose *published organization name is hand-typed by an operator from a letter's own text* as the only one recording nothing identifying at all. That is the path where an audit trail is worth the most, because the name being published is the least machine-derived. The letter position was available the whole time.

The `letter-` tag is load-bearing. Written bare, `{bill_id}-1` would be indistinguishable from the ordinary draft card's entry for draft index 1 on the same bill, and those name different things — a letter's position in the cleaned artifact and a draft's position in `draft_org_positions`. Two ID spaces sharing one field and one format is a collision waiting for whoever next reads the log.

nil remains correct for the third row, and is not the same defect: a caller asserting a position from its own knowledge names nothing in this bill's testimony, so there is nothing to record. An absent value that means "there is no such thing here" is fine. An absent value that means "the thing exists and we built the id from the wrong field" is not.

## Cross-file consistency

`#asserted_identity?` calls `BillLlmProvisioning.draft_identity_asserted?` rather than deciding on its own, so this class and `BillDraftOrgPositionsController` answer "did the caller name a draft?" identically by construction.

The two used to answer it separately, and had already drifted: an empty-string `draft_org_name` read as "asserts nothing" here and "asserts the empty name" there. Sharing one method closed that gap rather than relying on two comments that claimed to agree.
