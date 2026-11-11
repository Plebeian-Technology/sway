---
lat:
  mode: explanation
---

# The org-position card: editing and approval UI

Why the org-position card's stance label reads Neutral rather than Abstain, why the inline editor rebuilds from scratch and rides a rename along on Approve, and why the Approve button stays disabled rather than aria-disabled.

## Why SUPPORT_LABEL says "Neutral", not "Abstain"

One word per stance, and the same word everywhere on this card.

The badge used to read "Abstain" for the value the edit menu below offers as "Neutral", so an operator picked one word and the card answered with another. The stored value is "neutral" and the schema knows only that, so "Neutral" is the one that matches everything else.

The keys are the card's own three-way vocabulary, used nowhere outside `constants.ts` and `BillCreatorOrgPositionCard`.

## Why the inline editor keeps its own copy of the values

The inline edit form for one organization position keeps its own copy of the values being edited, so Cancel throws them away without disturbing the parent.

The parent hears about edits only through `onSave`, and it rebuilds this component from scratch every time Edit is toggled, so there is no need to copy props back into state.

Renaming the organization happens here too, and like the stance and summary it stays in the browser until Approve. The Approve request already carries the organization name, so a rename needs no request of its own — it rides along on that same single round trip.

## Why the Approve button stays a real disabled attribute

The HTML ids, separated by spaces, of the notice or notices explaining WHY Approve is off: this card's retraction mark, the bill-level no-testimony notice, or both. Undefined when Approve is available.

The button keeps a real `disabled` attribute on purpose, instead of switching to `aria-disabled`, so that it stays focusable. Approve is the step that publishes an organization's position, and such a position has to be backed by testimony. A real `disabled` attribute guarantees the click cannot happen; `aria-disabled` plus a JavaScript check swaps that guarantee for a convenience. A description is still read out on a disabled button, so a screen reader that reaches it while reading through the page — which is how pages are actually read, rather than by tabbing — announces the reason.

See [[docs/explanation/org-position-approval-guard-chain.md|The approval guard chain]] and [[docs/reference/evidence-retraction-writers.md|Evidence-retraction writers]] for the three server-side reasons Approve can be refused that this button greys out on: evidence retracted, no bill-level testimony on file, and a queued or running summary run in flight.
