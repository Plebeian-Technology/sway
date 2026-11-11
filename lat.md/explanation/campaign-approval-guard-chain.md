---
lat:
  mode: explanation
---

# The campaign approval guard chain

`ApproveCampaignPositionService#call` is the only path that turns a campaign draft — a reuse draft the clean-testimony stage collapsed out of a bill's hearing testimony — into a stored `Campaign`.

It never creates an `Organization` row: the defect behind that rule was approving a campaign through the org-name field, so a coalition of 221 letter-writers became an Organization a reader could follow. A sender's own words stay with the campaign and never become a followable record named after that person.

This class is built as a deliberate mirror of `ApproveOrgPositionService`. Most of its structure — the pre-check/re-check split, the lock that makes the re-check authoritative, the reason a bail must raise rather than skip — is the same machinery for the same reasons, and is documented once in [[docs/explanation/org-position-approval-guard-chain.md|The approval guard chain]]. This document covers only what the campaign path does differently, and why.

## Why summary validation runs first

An operator may clear the text while still drafting it elsewhere on this screen, but Approve is different.

An operator may clear the text while still drafting it elsewhere on this screen, but Approve is different — `#upsert_campaign`'s `save!` runs the model's `summary` presence validation, and a blank value here would otherwise raise an unrescued `RecordInvalid` instead of answering with a message the operator can act on. This mirrors `ApproveOrgPositionService`'s identical guard and its placement first, before any other check runs.

## Identity is mandatory, with no exempt caller

This is where the class genuinely diverges from its sibling.

In `ApproveOrgPositionService` draft identity is optional, because `BillsController#approve_org_position` is a real non-UI caller asserting a position from its own inputs, with no draft involved at all — the exemption documented in [[docs/explanation/org-position-draft-identity-exemption.md|Draft identity and the approval exemption]].

Here the campaign card is the only caller and always names a draft, so a request without one is not a caller class to exempt. And every guard below reads that draft, so exempting one would skip all of them — coverage gate included — and still write a public position. `#call` refuses a blank `content_hash` outright, so no check below needs a "skip this when identity is absent" guard.

`content_hash` is `TestimonyCampaignDraftResource`'s own content hash for a draft — the draft's stable id, assigned by `Testimony::CampaignDraftFinder` and `Testimony::CampaignMarker`.

### Why position is not part of the identity

The card once sent an `:index` alongside the hash, and both had to agree or the approval was refused.

That made the array's ORDER load-bearing for identity, which it is not built to be: a clean-testimony re-run rebuilds `campaign_drafts` wholesale, and a draft whose own text never changed can come back at a different position because some other draft appeared, merged or vanished.

An operator approving that unchanged draft was then told it "has changed since the page loaded" and refused — a correct approval turned into a false mismatch by a re-run that did nothing to the draft in question (W6).

The hash does not have that problem, because it is a digest of the draft's own reused text. Two coordinates were never two independent checks — the index was only ever used to look up the entry whose hash was then compared — so dropping it removes a failure mode without weakening the guard. The single remaining refusal, `:draft_not_found`, means what the old pair was trying to say: no draft in the bill's current artifact carries this id.

## run_in_flight?

A queued or running clean-testimony run can rewrite the cleaned artifact's `campaign_drafts` array wholesale, so a draft it is about to replace must not become a public position first.

A queued or running clean-testimony run can rewrite the cleaned artifact's `campaign_drafts` array wholesale, so a draft it is about to replace must not become a public position first — the same rule `ApproveOrgPositionService` enforces for `draft_org_positions`.

The check reads `LegislationPipelineRun.cleaning_testimony_for`, not only the provisioning row's own status. `provisioning.pending?`/`generating?` is the LLM SUMMARY job's state, not `Testimony::CleanAndGroupService`'s, so the pipeline-run lookup is what actually answers the question this guard is asking (B7). `ApproveOrgPositionService#run_in_flight?` carries the same fix.

## no_testimony

Every draft this card can act on was cut out of the bill's testimony, so testimony that has since gone leaves nothing to publish from.

The organization sibling has refused on this from the start — see [[docs/explanation/org-position-bill-testimony-check.md|The bill-level testimony check]] — and this service was the one approval path that would still succeed against it.

## Why the coverage gate runs last

`:coverage_not_acknowledged` is placed LAST among the pre-transaction checks, like `ApproveOrgPositionService`'s own sixth guard.

It reads `Testimony::CoverageReport` — a fresh read of the cleaned artifact plus an acknowledgement-table lookup — which is a heavier read than the boolean flags above it, so a caller that trips an earlier, cheaper refusal never pays for it.

## Nothing to write back

The organization chain's re-check exists partly to guard a read-modify-write of the whole `draft_org_positions` array.

There is no such array here: campaign drafts are read fresh from the cleaned artifact and never stored as their own mutable list, so `#reconfirm_guards` only raises or returns. It has nothing of its own to persist.

The transaction still matters. It wraps the upsert and the decision log so a failure partway through rolls back a freshly-created `Campaign` along with everything else, and so the in-transaction re-checks see a truly locked row.

## Which campaign gets written

Matching an approval to an existing campaign is a separate question, covered in [[docs/explanation/campaign-scope-and-identity.md|Campaign scope and identity]].
