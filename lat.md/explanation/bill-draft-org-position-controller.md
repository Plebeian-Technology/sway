---
lat:
  mode: explanation
---

# Bill draft organization-position controller

The admin endpoint makes decisions on draft organization positions stored as entries in a provisioning row's JSON array.

## Composite ids address one entry in the stored array

The route id is a bill id and a zero-based array index joined by a hyphen; malformed values receive a 422 before bill lookup.

[[app/controllers/bill_draft_org_positions_controller.rb#BillDraftOrgPositionsController#parse_composite_id]] rejects malformed ids instead of coercing them into a different resource lookup. The entry has no database id, so edits and rejects must also identify its content before changing the indexed slot.

## Draft identity separates a moved entry from a removed one

The client can identify an entry by its content token or its organization name, and the controller checks that identity before applying a change.

[[app/models/bill_llm_provisioning.rb#BillLlmProvisioning#draft_identity_asserted?]] defines whether a request named an entry; [[app/models/bill_llm_provisioning.rb#BillLlmProvisioning#draft_token]] distinguishes entries even when names match. A rejected draft that is gone is an idempotent success, while a named draft found elsewhere means the list moved and returns an Inertia error without modifying the array. A request naming no draft is refused as incomplete.

## Draft edits are validated at the controller boundary

Edits accept only schema-approved stances and bounded free-text values, while an empty summary remains a valid edit.

The controller is a writer that merges named fields into a JSON array rather than rebuilding a schema-validated payload. [[app/models/bill_llm_provisioning.rb#BillLlmProvisioning#draft_support_valid?]] and [[app/models/bill_llm_provisioning.rb#BillLlmProvisioning#draft_text_too_long?]] therefore guard that path. An edit naming no fields is refused so it cannot write a false edit decision to the activity log.

## Non-admin rejection is checked for both response and stored state

The request spec verifies a non-admin is returned to the root and the draft array remains unchanged.

[[spec/requests/bill_draft_org_positions_idempotency_spec.rb]] uses an active representative link so authentication admits the user and the admin guard is the refusal under test. This direct state assertion proves the rejected action did not remove the draft.
