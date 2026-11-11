---
lat:
  mode: explanation
---
# Private-individual guard override

The private-individual guard can wrongly refuse a real organization, so the operator — the final arbiter of what gets published — can confirm past the same warning and approve anyway.

The guard first left an admin asserting a position from their own knowledge exempt from the guard entirely, reasoning that a wrong refusal there would permanently block a legitimate assertion with nothing on screen to overrule it. The testimony-sourced path can refuse wrongly too, so it gets the same relief — explicit, confirmed, and logged, rather than a second silent exemption.

## Honoured at both check sites

`ApproveOrgPositionService` reads `@override_private_individual` at the fast pre-check in `#call` and at both authoritative in-transaction re-checks.

The draft path (`#delete_approved_draft`) and the claimed-affiliation path (`#reconfirm_claimed_affiliation_guards`) share one re-check method, `#guard_private_individual!`, so the two cannot drift apart the way two independent copies of the same condition eventually do. Only the pre-check is an optimization; a stale browser tab that reloaded before a `fetch-hearings` run rewrote the cleaned artifact would see the confirmed warning but no longer be describing the letters the re-check actually reads, so the flag has to be re-evaluated against the row `#with_lock` just reloaded, exactly like every other guard in this class.

## The override reaches one guard, not the whole chain

`@override_private_individual` is read only inside `#guard_private_individual!` and its matching pre-check condition.

Every other refusal in the chain — a stale draft index, retracted evidence, no testimony, a run in flight, an unacknowledged coverage gap — still fires with the flag set, because none of them read it. An operator who confirms past a resident's name being read as an organization has said nothing about whether the testimony behind the draft is still there.

## Recorded in the activity log only when it mattered

`@private_individual_override_used` starts false and flips true only when the guard's condition was actually true and the override let the approval through.

`#log_decision` adds `private_individual_override: true` to the `org_position_decision` entry precisely then — not whenever the request happened to carry the flag, since an operator can send `override_private_individual: true` on a draft the guard was never going to refuse. The log entry exists to say when the override was consequential, not when it was merely offered.

## Approve-anyway lives behind the app-wide confirm dialog

`BillCreatorOrgPositionCard` and `BillCreatorClaimedAffiliationCard` reach the override through `useConfirm`, the single confirm dialog `App.tsx` mounts around the whole application, rather than a second Approve button beside the first.

A dialog is what makes the override deliberate. The operator reads the refusal they just received and the consequence of overruling it — the name becomes a followable organization — and answers that question, instead of clicking a control that happens to sit next to the one that was refused.

The cost is a shared dependency: `useConfirm` raises outside `ConfirmProvider`, so a card rendered on its own in a test brings the whole suite down unless that suite supplies the provider or stubs the card. `BillCreatorLlmSummaryStatus` and `LlmSummaryOrgPositions` render the real cards and so wrap their renders in the provider; `BillCreatorPipelineLlm` stubs the card instead, which is the other way out.

## A retry started from onError outlives the request that started it

The override retry is sent from inside the refused request's own `onError`, so two requests overlap and a card that tracked one boolean per request re-enabled its buttons mid-retry. [[app/frontend/hooks/useInFlightRequests.ts#useInFlightRequests]] counts them instead.

Inertia awaits what `onError` returns before finishing the visit. `handleApproveError` is `async` and waits on the confirm dialog, so the refused request stays open for as long as the dialog is on screen — which is the behaviour the card wants, because it keeps Approve, Reject and Edit disabled while the operator decides.

What it does not survive is the answer. Confirming calls `submitApprove(true)` synchronously and returns, which settles the first request's `onError` and lets its `onFinish` run — and that `onFinish` fired a bare `setSubmitting(false)` while the retry it had just spawned was still on the wire. Every action on the card came back to life for one network round trip. A second Approve in that window re-sends without the override and is refused again; a Reject in it races the retry against the same draft, and which one wins depends on which response lands first.

Counting requests rather than flagging one fixes it at the root, because the count only reaches zero when nothing is left in flight. The alternative — having the retry suppress the first request's `onFinish` — encodes the ordering of two callbacks in a library this code does not own, and would have to be re-derived every time that library's promise chaining changes.

## A refusal that survives the override is shown, not re-asked

`handleApproveError` takes the override state of the request that failed, and only offers the dialog when that request did not already carry the flag.

A retry sent with `override_private_individual` cannot be refused by this guard again — the service reads the flag at every check site. So a private-individual refusal arriving on a request that already carried it means something else is wrong, and the honest response is to put the message in front of the operator. Re-opening the same dialog would ask them to confirm a decision they have already made, against a server that is not listening to it.
