---
mode: explanation
summary: "Test-setup rationale for BillCreatorOrgPositionCard.test.tsx: element-id collisions, stance-label wording, and other fixture and assertion choices."
status: agent-extracted
related: ["docs/terminology.md"]
---

# BillCreatorOrgPositionCard test notes

## Row element ids must not be built from the organization name alone

The organization name alone built each row's element id, so two positions from one
org — perfectly normal — got duplicate ids, and renaming an org moved a test's target
mid-edit.

The badge used to read "Abstain" for the stance the edit menu calls "Neutral"; the
stored value is "neutral", which the schema is the only authority on. See
`docs/terminology.md` for the canonical Support/Oppose/Neutral vs FOR/AGAINST/ABSTAIN
split.

## An evidence-retracted draft still allows Reject and Edit

When a hearing's testimony is withdrawn, evidence_retracted_at is stamped on every
affected draft; the card explains why Approve is refused before the click.

Reject and Edit stay available — Reject retires the dead draft, and Edit publishes
nothing.

## Bill-wide no-testimony is a second, separate refusal reason

The second refusal reason, one the per-draft mark can't express: clearing supplemental
testimony leaves drafts in place, so Approve greys out based on a fact about the BILL.

The reason is stated once by LlmSummaryNoTestimonyNotice at the top of the list, not
repeated on every card, because it is a statement about the bill.

## A disabled Approve must carry its reason into the accessibility tree

A greyed-out Approve is skipped by Tab, so a screen-reader user can only learn the
reason via aria-describedby — which the button didn't have.

The two reasons live separately — withdrawn-testimony on the card, bill-wide
no-testimony stated once by LlmSummaryNoTestimonyNotice — and aria-describedby
accepts multiple ids for both. (C1-i6-IN-04)

(`app/frontend/components/admin/creator/__tests__/BillCreatorOrgPositionCard.test.tsx`)
