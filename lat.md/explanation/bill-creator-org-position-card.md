---
lat:
  mode: explanation
---

# BillCreatorOrgPositionCard mechanics

Why BillCreatorOrgPositionCard requires testimonyMissing/runInFlight with no default.

## Why testimonyMissing is required, with no default

True when the BILL has no testimony at all (provisioning.has_testimony is not true). An absent answer counts — callers test `!hasTestimony`, not `=== false`, since the wire payload can omit the key.

Different question than the per-draft evidence_retracted_at mark: a bill can have testimony while one draft's own evidence was cleared, or have none while its drafts were never marked.

Required, not optional with a default — an unanswered value here would mean "approvable", and a control that quietly defaults to permissive is the bug class this file keeps guarding against.

`runInFlight` is required for the same reason: an unanswered value here would mean "approvable".

## Why the component works the way it does (no reload after Approve/Reject)

A card for one draft organization position. Approve, Reject, and Edit show nothing as done until the server confirms it; a local `submitting` flag disables the buttons meanwhile.

Approve and Reject work by redirect to summary_bill_creator_path; its GET redraws the page with fresh `bill` props (draft_org_positions already without this entry) — so neither fires its own reload.

Endpoints:

- `POST /bills/:id/approve_org_position { org_name, support, summary }`
- `PATCH /bill_draft_org_positions/:bill_id-:index { rejected: true }`

The Edit control opens a form that changes stance/summary locally, without saving; Approve then sends the edited values. There is no separate "save edit" call, keeping the operator to one round trip.

News-sourced draft positions display source links through `source_url`. The link is validated client-side with `isSafeUrl`, rendering inert text if the URL does not use standard web protocols (`http:` or `https:`) to prevent linking to local or dangerous protocols.

## Why handleApprove sends both index and the original draft identity

Sends `index` so the server can drop the matching entry from draft_org_positions — without it the card stays on screen after approval. Same id scheme as handleReject below.

No notify() call on success: the message comes from the server's own flash\[:notice] ("Approved <Org> on <bill>."), matching how Reject and Edit report back.

`draft_org_name` is the draft's ORIGINAL name, not a renamed edit — the server compares it against draft_org_positions\[index] and refuses on a mismatch, so a stale index can't delete the wrong draft.

`draft_token` outranks the name and is the ORIGINAL token, so a rename here can't invalidate it. See [[docs/explanation/draft-org-position-identity.md|draft-org-position-identity.md]] for how the token itself is computed.

## Why handleApprove's onError spells out all 8 refusal reasons

ApproveOrgPositionService can refuse 8 ways (:org_name_required, :invalid_stance, :identity_required, :draft_index_required, :draft_index_mismatch, :evidence_retracted, :no_testimony, :run_in_flight).

The list is spelled out so a new outcome mapped to a different key gets noticed here — nothing on this screen renders props.errors otherwise, so a refusal would look like a slow request.

The handler handles :evidence_retracted specifically because approveDisabled cannot prevent retractions occurring between page rendering and click time. See [[docs/explanation/org-position-approval-guard-chain.md|org-position-approval-guard-chain.md]] for the guard chain itself.

## Why handleReject carries the same original identity as Approve

Reject carries the same ORIGINAL identity as Approve. `submitting` covers only this card, so a second card's Reject can land first.

After that, this card's `index` may point at a different draft — token is checked first, name as fallback.

BillDraftOrgPositionsController#update refuses an out-of-date Reject the same way, with the same wording.

## Why the card's DOM id (slug) is org_name + index, not org_name alone

Has to be both STEADY and ONE OF A KIND. `org_name` alone is neither: nothing limits an org to one position, and two testimony letters from one coalition is routine.

A name collision would give two elements the same id and break Capybara's within(...).

`orgName` is the operator's editable text, so a rename mid-edit would move the id if used alone — `index` (server identity) plus the original `org_name` stay steady.

## Why the stance badge falls back to the stored word instead of hiding

TStance claims one of three words, but the wire doesn't enforce it — a row written before the controller started refusing unknown stances can hold anything, and TypeScript can't check JSON at runtime.

With no fallback, both lookups below returned undefined and the badge drew empty with no tone, so the operator only learned something was wrong when Approve refused.

Tone falls back to neutral and the badge shows the STORED word (not a guess), so the operator can see what's actually on the row and reject or edit it. A blank stored value is named as "No stance".

## Why the evidence-retracted notice names no specific cause

No cause is named: five different writes stamp this mark and the screen can't tell which. See [[docs/reference/evidence-retraction-writers.md|evidence-retraction-writers.md]] for the catalog.

Naming "the latest hearing fetch" here used to be wrong for the common case — an operator clearing their own paste — sending them to re-run a fetch instead of regenerating.

## Why the notice AND the button both react to no-testimony

The notice explains; the card greys the button so a click can't waste a request that `ApproveOrgPositionService` would refuse with `:no_testimony` anyway.

## Why Reject and Edit stay usable when evidence is retracted

ApproveOrgPositionService refuses a draft marked this way, so the button that can't work is switched off with the reason written on the card, instead of failing only after the click.

Reject and Edit stay usable — neither publishes anything, and Reject is the operator's way out of a stale draft.

## Why testimonyMissing/runInFlight disable every card, even though the bill-level reason is written once

Second reason Approve can be refused, and the one the retraction mark above can't record.

The bill-level reason is written once by LlmSummaryNoTestimonyNotice, above the list — repeating it per card would be noise. But the button itself is disabled here, on every card, since that's where the click happens.

## Why approveDisabledReasonId is built as a filtered, joined list

A disabled button can't be reached with Tab, so this is the only way the reason reaches a screen reader.

The retraction notice id is per-card (via `slug`) since it belongs to this card; the no-testimony/run-in-flight ids are shared, since those notices are stated once for the whole list.

Both can apply at once, which is what aria-describedby's space-separated list is for — left undefined when Approve is available, so an enabled button never describes a state it isn't in.

## Why testimonyLeftOutUnacknowledged is derived once by the caller

The `testimonyLeftOutUnacknowledged` flag is true when testimony was left out (or the clean-testimony stage failed or never ran) and no acknowledgement matches the current numbers.

The caller derives this boolean once from the shared `testimony_coverage` prop rather than each position card computing it independently, so every organization, campaign, and claimed-affiliation card on the screen agrees with the single coverage notice above the list.
