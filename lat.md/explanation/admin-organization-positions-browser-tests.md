---
lat:
  mode: explanation
  require-code-mention: true
---

# Admin organization-position browser tests

The browser examples distinguish stored drafts, approvals, and operator-visible warnings.

## Conditional bill fixture

The shared cleanup hook removes summary artifacts for the bill only when an example materializes that bill. Tracking materialization inside the lazy fixture avoids creating a locale, district, and legislator just to clean a path that no example used.

## Rendering existing drafts is not a generation test

The card example writes draft positions directly to the provisioning fixture. It verifies rendering of existing rows; the summary-generation job's persistence contract belongs to its own service spec.

## Drafts without testimony are blocked

The empty draft list and stranded drafts have different outcomes. Drafts left after testimony disappears must be blocked.

## Retracted evidence is separately blocked

The retracted-evidence example retains testimony on the bill so it isolates the evidence-specific warning instead of repeating the bill-level no-testimony case.

## Exact counts pin organization reuse

The approval example asserts one organization with the expected name. A lower-bound count would pass if the near-match deduplication path created duplicate organizations.

## The edited approval uses a real control click

The example uses click_testid for the Radix select trigger so React receives the event and Capybara waits for the actual interaction. Its option is rendered in the page-level listbox, outside the card scope.

## The audit event records the decision only

The audit assertion checks that an approval event exists with the approved decision. Stance and summary remain authoritative on the position row and are not duplicated into the audit payload.

## Removing and re-adding restores unsaved position edits

The Bill Creator browser examples verify current form values across real position-removal requests.

### Card removal restores the current organization draft

The row button removes a saved position once; after the server response, re-adding the organization restores the unsaved support and summary values.

### Chip removal restores the current organization draft

The selected chip removes a saved position once; after the server response, re-adding the organization restores the unsaved support and summary values.
