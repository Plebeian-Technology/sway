---
lat:
  mode: explanation
---
# Taking an organization's position off a bill

An approved organization bill position is published: it appears on the bill, and the organization's followers were told about it. Removing one is an operator decision that has to reach the server, and it is a soft removal rather than a delete.

## Removal deactivates, it does not delete

`DELETE /organization_bill_positions/:id` sets the row's `active` flag to false and leaves everything else standing.

Three things depend on the row surviving. It owns its `OrganizationBillPositionChange` records, which are the audit trail of every edit the position went through — destroying the row would take that history with it. The follower-notification callback fires only while `active` is true after a change, so lowering the flag correctly sends nothing, where a delete would need its own suppression. And a bill reads its organizations through `active_organization_bill_positions`, so the flag alone is what makes the position visible or not.

The organization itself is untouched. Organizations are locale-level records shared across every bill in that locale, and one left holding no active positions is harmless; cascading into it would take an entity out from under bills that still name it.

Removing an already-inactive position is not an error. The row is left as it is and the operator gets the same answer, because a second click on a slow connection should not be a failure.

## What a reader sees once a position is switched off

`Bill#organization_bill_positions` returns only active positions, so the bill page's support and oppose cards carry those alone.

Nothing pinned what a visitor is left looking at once a position is switched off — by the bulk replace approving a new batch and deactivating the old one, for instance — until `spec/system/bill_org_positions_spec.rb` measured it in a real browser. The same spec covers the neighbouring rule for a bill's category tags, which are filtered to the active ones the same way.

## A draft with no testimony behind it is not approvable

A draft organization position is only approvable into a public row when
testimony exists behind it, and drafts predating that rule were stamped so they
stop being approvable.

The rule is provable rather than a date guess. The job only makes the positions
call when a bill's provisioning carries testimony, extracted or supplied by an
operator, so a row holding drafts while both testimony columns are empty cannot
have been written by the path that requires testimony. No timestamp is
consulted and none is needed.

Before the rule, the attachments were not in the prompt at all: the only
testimony input was the operator's own pasted supplemental text, and the prompt
grounded the positions field on exactly that, instructing the model to return
nothing when it was absent. So a row holding drafts with an empty supplemental
column holds positions the model was told not to produce, drawn from no
evidence of any kind.

A row that does carry supplemental testimony keeps its drafts. Widening the
rule to sweep those away would break the same principle from the other side,
since by that same prompt those drafts do have an evidence source. The boundary
is deliberate rather than a gap.

## A saved position is a published one

Every write path that puts an organization on a bill raises the `active` flag, the organizations panel's save included.

The flag is the only thing that makes a position visible: a bill reads its organizations through `active_organization_bill_positions`, and the panel itself is seeded from that same list. A path that wrote the row without raising the flag produced a position nothing could see — not the bill, not the public page, and not the panel that had just reported the save as done. The column defaults to false, so the flag has to be set rather than left alone.

An organization already on the bill is unaffected either way: its row is found rather than built, and it is already active. The panel only ever submits organizations that are in its list, and its list is the active ones, so raising the flag cannot resurrect something an operator removed.

## A Neutral position carries no testimony

An organization that is Neutral on a bill holds a position and no argument for it, so the testimony submitted alongside a Neutral position is discarded at ingestion rather than stored (`docs/terminology.md`).

Support and Oppose are claims, and the testimony is the case for the claim.
Neutral makes no claim, so text kept beside it reads on the bill page as an
argument the organization did not make. Discarding it at the point of ingestion,
rather than hiding it at display time, means there is one answer rather than a
stored value and a rule about when to show it.

`OrganizationBillPosition.neutral_support?` is the one place that answers whether
a position is Neutral, and every ingestion path calls it. The bulk replace and [[app/controllers/organizations_controller.rb#OrganizationsController#create]]
drop the submitted summary and no longer demand one. `ApproveOrgPositionService`
does the same before its own summary-required guard runs, which is what keeps a
Neutral draft approvable once its draft summary is gone — the rule sits in the
service rather than in the controller so every caller of the service gets it. The
draft editor drops the summary from a draft entry whose position is Neutral, so
the operator reviewing it is not shown an argument that will not be kept.

The value written is `OrganizationBillPosition::DEFAULT_SUMMARY`, the placeholder
the create path already uses, rather than nothing: the column is `NOT NULL` and
validated for presence, so an empty position cannot be stored without a
migration. The draft blob has no such constraint, so a Neutral draft's summary is
genuinely absent there.

## Nothing reads a Neutral position's stored placeholder

`OrganizationBillPosition#summary_for_readers` answers `nil` for a Neutral position, and every path that serializes a position asks it, so what is in the column to satisfy its `NOT NULL` constraint never reaches a reader.

There are three such paths and they serve different surfaces, which is why the
rule is one method rather than three conditions: `to_builder` (through
`to_sway_json`) feeds the bill page and the organization payload,
`to_public_json` feeds the public organization page, and
`OrganizationBillPositionResource` feeds the admin JSON routes and the bulk
replace's response. The column keeps the placeholder, because the constraint and
the presence validation both require one.

The key stays in every payload, because a client that finds the key missing
cannot tell a Neutral position from a payload that lost a field. Each surface
takes the null: the membership card falls back to an empty string when it seeds
its edit box, and the bill page, the public organization page and both mobile
lists render the paragraph only when there is text.

## Approval wire values share one storage mapping

The single-position form and bulk replacement accept the same stance vocabulary and map it to the stored enum values.

[[app/models/organization_bill_position.rb#OrganizationBillPosition#normalize_support]] maps `support`, `oppose`, and `neutral` to `FOR`, `AGAINST`, and `ABSTAIN`. [[app/services/approve_org_position_service.rb#ApproveOrgPositionService#call]] owns single-position validation, organization matching, upsert, draft removal, and the audit entry; [[app/controllers/bills_controller.rb#BillsController#approve_org_position]] maps its outcome to the Bill Creator response. [[app/services/replace_bill_org_positions_service.rb#ReplaceBillOrgPositionsService#call]] applies the same normalization to bulk replacement.

## A refusal reaches the operator as a message, not a 500

A position the service will not save is refused with a reason the operator can act on, rather than allowed to raise out of the save.

A blank summary used to reach the save unguarded and raise a validation error,
which answered the click with a 500 — and a blank string satisfies a not-null
column, so only a real presence check catches it at the edge. Refusing at the
submitting end also keeps the error off the approving admin, who was the one
seeing the 500 for somebody else's blank value.

Silence is the other half of the same rule. When the service declines, the card
stays on screen, so a no-op that says nothing simply reads as "click it again".

## Renaming an organization changes it everywhere in its locale

One organization record is shared across a locale, so an admin renaming it from the Bill Creator's organization panel changes the name shown on every bill in that locale.

That reach is why the rename is admin-only, and why the panel is the only place
it happens: the operator making the change is the one who can see what else
carries the name.

[[app/services/approve_org_position_service.rb#ApproveOrgPositionService#find_or_create_organization]] reuses an organization in the bill's locale when its name is sufficiently similar to the submitted name. This keeps a variation in spelling from splitting one shared organization and its positions across multiple records.

## Removal is recorded where the other decisions are

The action writes an `org_position_decision` activity-log entry with `decision: "removed"`, the same entry type approve, reject and edit already write.

An operator reading the log wants one place that answers "what happened to this organization on this bill". Splitting removal into its own entry type would put half that answer somewhere else, and the log's summary line is built from the decision word rather than from a fixed set, so a new word needs nothing added to render.

The entry is written only when the row was still active, inside the same branch that lowers the flag. A second removal of an already-removed position is a no-op that records nothing: the log is an account of decisions an operator made, and a double-clicked button or a retried request is one decision, so a second entry would report a removal that never happened.

## What the remove button can and cannot undo

Approving a draft position deletes the originating draft from the testimony artifact in the same transaction, so removing the position afterwards cannot bring the draft card back.

Re-adding the organization therefore goes through the manual organization panel rather than the guarded approval flow. That is a real limitation of the removal path and not a defect in it: the guard runs on drafts, and the draft is gone by the time there is anything to remove.

## The button only reaches the server for a position that exists

An organization added to the panel but not yet saved has no position row, and removing it is a change to the form's own list rather than a request.

The panel's list is seeded from the bill's saved organizations, so a row's `position_id` is present exactly when there is something on the server to deactivate. Sending a request without one would have nothing to name; dropping the row locally is the whole of the removal in that case. On the other branch the local drop happens only after the server answers, so a refused or failed request leaves the operator looking at what is actually stored.

## Both remove controls go through the same request

The panel offers two ways to take an organization off a bill — the card's Remove organization button and the small tag above it — and they share one hook rather than one calling the server and the other editing the form.

Two controls that look like the same action but only one of which reaches the server is the shape of the original defect: an operator uses whichever is nearer, and half the time the removal quietly undoes itself on the next load.

## Bill reader positions include their organization

The bill payload nests each active position's organization so the reader can label the stance without a second lookup.

[[app/models/organization_bill_position.rb#OrganizationBillPosition#to_builder]] builds the position data used in the bill's `organizations` prop, including the organization object. The frontend type extends the shared position shape with that nested organization, while the summary and AI-review flag remain position fields.

## Position lookup stays within the organization

[[app/controllers/organizations/positions_controller.rb]] and [[app/controllers/organizations/position_changes_controller.rb]] constrain lookups to the organization in the URL.

Membership in one organization cannot authorize changes to another organization's position or approval queue. Both lookups also join visible bills under [[bill-session-archiving#Active views]], so retained archive history cannot be proposed, approved or removed through these endpoints.

## Organization position admin endpoints expose drafts

Every action in [[app/controllers/organization_bill_positions_controller.rb#OrganizationBillPositionsController]] is admin-only because the collection can include inactive positions that have not been approved for public readers.

The public bill and organization views use active positions only. Returning draft rows from these administrative endpoints to an untrusted reader would expose text the organization has not approved. The browser receives the data through the admin surface; the public organization reader has its separate active-only contract.

## Organization position JSON preserves its empty shapes

The positions API keeps its established body shape when a requested row is missing or a batch contains no changes.

`show` returns JSON `null` with HTTP 200 when no position matches; successful results pass through [[app/serializers/organization_bill_position_resource.rb#OrganizationBillPositionResource]], with the whitelist rationale owned by [[system-shape#One process, two languages#Why a payload goes through a resource rather than the record]]. An empty batch returns 204 with no body, while failures use [[app/controllers/concerns/json_error_renderable.rb#JsonErrorRenderable#render_error]]'s standard envelope.

## Bulk position writes stay behind the service boundary

[[app/controllers/organization_bill_positions_controller.rb#OrganizationBillPositionsController#create]] delegates whole-batch validation and persistence to [[app/services/replace_bill_org_positions_service.rb#ReplaceBillOrgPositionsService#call]], then translates its result into an HTTP response.

The service validates the batch before writing and owns position upserts and deactivations; keeping those decisions outside the controller gives every caller one write policy. The failure result's `error` and `message` are nilable for the success and empty variants, so the failure branch stringifies them to meet the non-nil `render_error` inputs after narrowing by result kind.

A missing `organization_id` is an incomplete position, reported as `incomplete_position` with HTTP 422 before any row is written. [[app/services/replace_bill_org_positions_service.rb#ReplaceBillOrgPositionsService#call]] validates the complete batch, and [[app/controllers/organization_bill_positions_controller.rb#OrganizationBillPositionsController#create]] returns that failure through the JSON error envelope.
