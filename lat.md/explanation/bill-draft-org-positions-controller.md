---
lat:
  mode: explanation
---

# BillDraftOrgPositionsController

Admin-only endpoint for deciding what happens to a draft organization position on a bill.

No `BillDraftOrgPosition` model exists: a bill's draft positions live as a JSON array in `draft_org_positions` on its `bill_llm_provisioning` row, filled by the `paste_summary` action and the summarize stage of `RunLegislationPipelineJob`.

## The composite id

`:id` is `"<bill_id>-<index>"`.

`PATCH` either rejects that entry or edits its `org_name`/`stance`/`summary`, and either way writes one `org_position_decision` line to the activity log via `PipelineActivityLogger.log_org_position_decision!`.

## Which paths are actually exercised

`reject` is used for real, by `BillCreatorOrgPositionCard`'s `handleReject`.

`edit` is exercised only by specs — the card's real save path is `handleApprove`, which carries its own amended values — but the edit branch stays because a route only counts as dead when nothing (web/mobile/API) calls it, and it is where the card's own Save will land once it stops being browser-only.

## Why this endpoint answers in JSON

This endpoint is JSON-first, which is unusual in this codebase: refusals render a bare JSON 4xx, and only `:identity_mismatch` and the happy path redirect with Inertia errors.

Every JSON branch is unreachable from the live card, which always sends a token and a machine-built composite id — see `BillsController#render_paste_summary_errors` if this endpoint ever needs to serve both surfaces.

## Why a malformed id is a 422, not a 404

`parse_composite_id` is anchored (`\A(\d+)-(\d+)\z`) so the caller gets a 422 that spells out the shape expected (`"<bill_id>-<index>"`.

`parse_composite_id` is anchored (`\A(\d+)-(\d+)\z`) so the caller gets a 422 that spells out the shape expected (`"<bill_id>-<index>"`, both positive integers) instead of `.to_i` quietly turning junk into zero and 404'ing on `Bill.find(0)`, which would explain nothing. `#update` checks the parsed result for `nil` before doing anything else, for the same reason.

## Reject is idempotent; edit is not

A reject on an already-gone draft counts as done, not an error — a fast double-click can resend the same reject.

Redirecting with "Already removed" keeps Inertia's success path instead of a jarring 404 reload. An edit on a missing draft still 404s, since editing something absent is a real client mistake. "Genuinely gone" is verified in `#apply_draft_decision` rather than inferred from the index, because deleting shifts every later index down by one.

## Why this endpoint's admin guard is tested with a non-real bill id, and why the message says "look at the list", not "reload"

This controller declares `before_action :verify_is_sway_admin` and appears in the admin-guard lint list.

This controller declares `before_action :verify_is_sway_admin` and appears in the admin-guard lint list, but its request spec used to run entirely as an admin, leaving it the one listed controller with nothing proving non-admins are turned away. The non-admin coverage in `spec/requests/bill_draft_org_positions_idempotency_spec.rb` targets a bill id of `"1"` that need not exist: the admin check runs before the id is looked up, so a non-admin is blocked without touching the database at all.

When a reject or edit request names an out-of-range index, `#update` reports "Draft already removed" only when the named draft is genuinely gone. When the named draft is still in the array — just at a different position, because deleting shifts every later index down by one, which is the COMMONEST way to reach an out-of-range index, not a rare one — the message instead tells the operator the list moved and to look at it. It does NOT say to reload: no Bill Creator surface may ask for a manual reload, and this refusal never needs to, because the redirect that reports the refusal already carries the current list.

## Why the idempotency spec exists as a request spec, not a browser spec

`spec/requests/bill_draft_org_positions_idempotency_spec.rb` began as a browser (system) spec.

The browser stack for the bill edit page has an unrelated flake, and a request spec exercises the same controller with no browser involved, so it moved.

## Why an edit naming no field is refused

An edit naming no field is refused as a 422 (not silently applied): merging nothing would still write a false "edited" audit-log line, and that false trail is worse than a rejected request.

This is checked for missing fields, not empty ones — clearing a summary to `""` is a real edit. It's refused before `#apply_draft_decision` so it never takes the write lock.

## Field validation reuses the schema-derived limits

The stance and free-text length checks in `#update` are covered in [[docs/explanation/draft-field-validation.md|Validating fields on a draft org position]] — this controller's edit branch is the one writer of `draft_org_positions` those checks are not otherwise applied to.

## Why :identity_required is its own outcome, not :identity_mismatch

Sending a request that names no draft at all gets `:identity_required`, deliberately not `:identity_mismatch`.

Sending a request that names no draft at all gets `:identity_required`, deliberately not `:identity_mismatch`: that answer points the caller at a freshly reloaded list, right when the list shifted under them, but that's wrong here — the caller never named a draft at all, so a fresher list changes nothing. This belongs with the malformed-id 422 above: the request itself is incomplete. `ApproveOrgPositionService` draws the same distinction for the same reason — see [[docs/explanation/org-position-draft-identity-exemption.md|Draft identity and the approval exemption]].

## Locking in apply_draft_decision

`#apply_draft_decision` checks the index, checks the caller named the right draft, then changes it.

`#apply_draft_decision` checks the index, checks the caller named the right draft, then changes it — all inside one transaction that holds the row, via the identical `with_lock` / `default_transaction_mode: IMMEDIATE` mechanism `ApproveOrgPositionService#delete_approved_draft` uses — see [[docs/explanation/org-position-approval-guard-chain.md|The lock that makes the re-check authoritative]].

## Why identity is checked before bounds

Identity is checked BEFORE bounds, on purpose.

Checking bounds first meant a slot past the end was reported "already removed" without checking which draft was named — wrong whenever a concurrent reject shrank the array and shifted a still-pending draft down into range. Checking identity first also closes the same fail-open gap `ApproveOrgPositionService` had, where naming no draft at all could succeed as long as the index was merely out of range (see [[docs/explanation/org-position-approval-guard-chain.md|the hole a dropped `:index` left]]).

There is no nil check on the index inside `#apply_draft_decision`: `#update` already turns a malformed id away before this method is ever called, so a `nil` index can never reach this point.

## Two different answers for an out-of-range index

When the index is out of bounds, telling `:identity_mismatch` and `:already_removed` apart is the whole point of `draft_named_elsewhere?`.

If the named draft is still in the array, the list moved under the caller and reloading fixes it. If it is nowhere, it really was removed and saying so is honest. `draft_named_elsewhere?` scans the whole array since the index is what's being doubted, reusing the same identity comparison as the in-bounds path so the two paths can't disagree about what "this draft" means.

## Why both branches re-check identity against the entry at the index

Both the delete and the edit branch must prove the caller means the draft actually at this index — the same check `ApproveOrgPositionService` makes.

This is not just a two-operator race: each `BillCreatorOrgPositionCard` tracks its own `submitting` flag, so a click on one card can arrive with a stale, pre-shift index while a prior Reject's `router.reload` is still in flight, deleting or editing the wrong draft and mislabeling the audit entry. An index is not a name — it shifts by design — so acting on an unchecked one risks both a wrong change and a false record of it.

## Why decision is assigned from the if/else's value

`decision` is assigned from the `if`/`else` expression's value, not set inside each branch, so it is always a `Symbol`, never `Symbol`-or-`nil`, for the audit call that follows.

## Why reject deletes the entry instead of flagging it

Reject removes the entry outright rather than flagging it `rejected: true` in place — flagging meant the next mount of `BillCreatorLlmSummary` (which builds its list from props) sent the rejected card back.

Deleting keeps the array the single source of truth for pending drafts, but it shifts every later index down by one, so the frontend must refetch the bill prop after a reject or the next click aims at the wrong slot. That refetch is only a narrowing, not a guarantee — the identity check earlier in `#apply_draft_decision` is what actually refuses a shifted index.

## Why edit_params excludes :rejected

The edit branch gets its own narrow list of allowed fields (`org_name`/`stance`/`summary`) and must not accept `:rejected`.

The edit branch gets its own narrow list of allowed fields (`org_name`/`stance`/`summary`) and must not accept `:rejected` — a request labelled as an edit could otherwise quietly mark the draft rejected as well, once these values are merged into the entry, so this branch could not double as a reject.

## The activity-log Struct stand-in

`PipelineActivityLogger.log_org_position_decision!` is passed a small `Struct.new(:id, :organization_name)` instead of a real model, because the logger only ever reads `#id` and `#organization_name` off the draft it's given.

`PipelineActivityLogger.log_org_position_decision!` is passed a small `Struct.new(:id, :organization_name)` instead of a real model, because the logger only ever reads `#id` and `#organization_name` off the draft it's given — a stand-in carrying just those two values is all it needs.

## Why the success notice names the bill and organization

The notice after a decision names both the organization and the bill's `external_id` so operators with several tabs open can tell which draft they just acted on — it matches the detail already recorded in the activity log.

## Why an edited summary is marked

`draft_with_summary_edited` marks an entry only when the edit changes the summary text itself.

This is the same `DRAFT_SUMMARY_EDITED_KEY` mark documented in [[docs/explanation/internal-draft-marks.md|Internal marks on a draft org position]] — see "Why it exists" and "The rule" there for why approving later needs to know a person, not the model, wrote this text.
