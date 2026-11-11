---
lat:
  mode: explanation
---

# Organization position-change responses

The position-change controller preserves finalized decisions while giving browser and mobile callers the response shape each uses.

## Finalized changes receive the same refusal message

The approval and rejection services treat an already-decided row as a normal refusal, not as a second write.

[[app/controllers/organizations/position_changes_controller.rb]] uses one message for both actions: browser callers receive an alert and redirect, while JSON callers receive a 422 error envelope. The row's prior decision remains unchanged.

## Successful decisions preserve separate client protocols

Approving and rejecting change requests keep the audit row and return the established response for each client.

The controller redirect browser callers with flash; mobile callers receive 204 with no body. Rejection updates the audit status rather than deleting the row.

## The final-state helpers keep examples on one rule

The request examples use shared helpers to prepare approved and rejected rows before exercising a repeated decision.

Those helpers set the fields that make each row final, keeping the setup consistent across both response formats. [[app/services/approve_position_change_service.rb]] and [[app/services/reject_position_change_service.rb]] reload the row under a lock and check the final state again before writing, so only the first concurrent decision can succeed.

## Position submissions remain proposals until approval

An active member may propose a position change, while only an organization admin may remove a position directly.

[[app/controllers/organizations/positions_controller.rb#PositionsController#verify_is_active_member!]] guards create, new, and update. Those writes create or reuse a pending [[app/models/organization_bill_position_change.rb#OrganizationBillPositionChange]]; an administrator's approval service applies the proposal. Rejected or approved changes are finalized and cannot be edited again.

## Position changes expose decisions without a collection route

The position-change routes permit update and destroy but provide no index action for listing approval records.

The controller has no index action, so a collection listing would need its own authorization, response-format, and refresh contract. Existing decision lookups remain scoped to the organization in the URL, as documented by [[organization-position-removal#Taking an organization's position off a bill#Position lookup stays within the organization]]. [[app/controllers/organizations/position_changes_controller.rb]] owns the individual decision actions.
