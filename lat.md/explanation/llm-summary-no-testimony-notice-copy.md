---
lat:
  mode: explanation
---

# Why LlmSummaryNoTestimonyNotice reads the way it does

Explains the three wordings LlmSummaryNoTestimonyNotice draws between (nothing generated.

## hasDrafts

Whether any draft cards are drawn below — missing testimony means a different thing depending: why nothing generated, or why what's shown can't be approved.

## allDraftsRetracted

True when every draft is marked as having lost its evidence. Not cosmetic: pasting testimony back does NOT lift the mark — the server refuses at the end of that path. See [[docs/explanation/org-position-bill-testimony-check.md|org-position-bill-testimony-check.md]].

## NOTHING_GENERATED: names the field, not a direction

Names the field rather than a direction: "below" was wrong since `SupplementalTestimonyField` renders ABOVE this list.

## DRAFTS_RETRACTED: pasting back does not help

MARKED drafts (lost evidence) can not be fixed by pasting back — only Regenerate/Reject work. This used to say the opposite. When NOT marked, pasting testimony in is a real way forward.

## Why the component moved out of the empty-list branch

Used to live in the branch that only ran when `orgPositions.length === 0` — so the cards it needed to warn about hid it. Clearing testimony can leave drafts with a working Approve and no warning.

## Test note: naming the field, not just the click

Typing into Supplemental testimony writes nothing on its own; naming only the field left the operator thinking the paste alone had done something.

`LlmSummaryOrgPositions.test.tsx` asserts both "Paste the testimony back" and "click Save testimony" appear together.

## The id and aria-describedby

Every card's greyed-out Approve aims its `aria-describedby` here, since a disabled button can't be reached with Tab — without the pointer, a screen reader meets a dead control unexplained.

See [[docs/explanation/llm-summary-notice-id-coordination.md|llm-summary-notice-id-coordination.md]] for why the id lives in its own file, and [[docs/explanation/bill-creator-org-position-card.md|bill-creator-org-position-card.md]] for how each card's `approveDisabledReasonId` assembles this id alongside the per-card retraction id.
