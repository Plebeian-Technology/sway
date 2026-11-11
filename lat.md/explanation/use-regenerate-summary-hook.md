---
lat:
  mode: explanation
---

# Why useRegenerateSummary is built the way it is

Shared state for the "Regenerate summary" button: it posts to `/bills/:id/regenerate_summary` and holds a loading flag on for the length of the request.

Both `BillCreatorLlmSummary` (when a summary already exists) and `LlmSummaryEmptyState` (when there is no pipeline data) use it; each used to carry its own identical copy of this state and handler.

## Why supplementalTestimony is passed conditionally

`supplementalTestimony` is sent whenever the caller has a supplemental-testimony box on screen.

When a summary is stale, the button in the stale header is the only regenerate the operator can reach, and it is the one the testimony-attachment warning points them at, so whatever they pasted has to travel with the request or the server discards it. Passing `undefined` (the empty state, which has no such box) sends no key at all, and the server leaves the stored value alone.

## Why onError lives in the hook, not at each call site

The server refuses this request in two cases — no pipeline data to work from, or a generation already running — and reports both as `errors: { generation: <message> }` with no flash alert.

Nothing appears on screen unless the browser reads that error out. This hook is the one path behind both regenerate buttons (the stale header and the empty state), so the handler belongs here rather than being copied into each of them, which is how the two identical versions this hook replaced drifted apart in the first place.

## Why onSuccess exists even though onError already covers refusals

The expiry rescue redirects BACK, which is a successful Inertia visit, so `onError` never sees it.

Nothing here claimed a false success — the shared flash toast still fires — but a button that buys two model calls left the operator with a generic banner as their only sign that nothing had started: the busy flag cleared, the button came back, and the badge never moved to "Queued…". The control they used now says so itself.

See [[docs/explanation/bill-creator-test-fixture-overrides.md|bill-creator-test-fixture-overrides.md]] ("An expired-page Generate failure needs its own banner") for the sibling defect on the Generate button, which the same fix also covers.

## The lapsed-session check inside onSuccess

Same seam as the summary save and Generate: a lapsed admin session redirects to `root_path`, a successful Inertia visit `onError` never sees, and this button also buys two model calls.

See [[docs/explanation/bill-creator-landed-write-detection.md|bill-creator-landed-write-detection.md]] for the general pattern this check follows, and [[docs/explanation/page-expired-flash-flag-and-c21-01.md|page-expired-flash-flag-and-c21-01.md]] for why `pageExpired` is checked first.

## useRegenerateSummary.test.ts notes

The server signals a regenerate refusal only via redirect `errors: { generation }`, never a flash alert. This hook is the one path both regenerate buttons use, so the handling lives here once.

An expired-page redirect is a successful Inertia visit, so `onError` never fires — without this check the busy flag clears with no notice of the refusal at all.

The other side of the wire: an ordinary landing must stay silent, or a handler that toasted on every visit would pass the example above.

A lapsed admin session redirects successfully via `root_path`, invisible to `onError` and unflagged, so this hook must also check `landedOnBillCreator` like its sibling regenerate buttons.
