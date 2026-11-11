---
mode: explanation
summary: "Explains why LlmSummaryOrgPositions is memoized, why testimony presence is checked with a fail-closed negation, and why allDraftsRetracted requires every draft rather than some."
status: agent-extracted
related: [docs/explanation/llm-summary-no-testimony-notice-copy.md, docs/explanation/unique-stable-keys-react-list-identity.md, docs/explanation/bill-creator-llm-summary-actions.md]
---
<!-- vale Vale.Spelling = NO -->

# Why LlmSummaryOrgPositions is built the way it is

Wrapped in `memo` so the textarea beside it doesn't redraw every card. The
no-testimony notice used to sit inside the empty-list branch, hiding it
exactly when items needed the warning most. See
[llm-summary-no-testimony-notice-copy.md](llm-summary-no-testimony-notice-copy.md)
for that notice's own copy.

## `noTestimony` fails closed

`!hasTestimony`, not `=== false`: an omitted wire key sends `undefined`,
and the strict test would read that as "has testimony", wrongly enabling
Approve. This direction must fail closed.

## `allDraftsRetracted` requires every draft, not some

Every draft, not some: the notice speaks for the whole list, and a mixed
set means the paste advice is still true for at least one card.

Mixed marks keep the paste advice, because it is still true for the card
that has no mark.

## `testimonyMissing` defaults to "no testimony"

`testimonyMissing` must default to "not testimony": `BillCreatorOrgPositionCard`
treats anything but literal `false` as "has testimony", so an unanswered
value must not read as safe.

The cast matters: TypeScript declares this prop boolean, but a JSON
payload that omits the key hands the component `undefined` at runtime
regardless of the type.

## `runInFlight`

True when a run is queued or running over the drafts drawn below.

## Test notes (LlmSummaryOrgPositions.test.tsx)

The stub card holds local edit state via useState, just like the real
card — so it needs a React key, or a rebuild silently drops whatever the
test typed.

runInFlight defaults false — this suite tests the testimony gate.
The in-flight gate has its own examples in
BillCreatorLlmSummaryStatus.test.tsx.

Drafts marked evidence_retracted_at stay refused by the server even after
testimony is re-pasted — the notice must say to regenerate, not paste,
and sits first.

Every card's aria-describedby points at this exact id; if the notice
drops it, all those pointers resolve to nothing. Checked card-side in
BillCreatorOrgPositionCard.test.tsx.

Approve/Reject shifts every LATER entry's rawIndex down by one on the
follow-up GET. Keying a card on rawIndex remounts it, silently dropping
unsaved edits.

draft_token is optional — a payload that skips
BillLlmProvisioning#to_builder omits it. The fallback key must derive
from content too, or this bug recurs.
