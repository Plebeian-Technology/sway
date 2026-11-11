---
lat:
  mode: explanation
---

# Why paste_summary_bill_payload uses to_sway_json

`paste_summary_bill_payload` builds the bill payload the `paste_summary` 200 response sends back, so mobile can refresh its local cache without a follow-up GET.

It builds `bill_llm_provisioning` with `#to_sway_json` — the same call the Inertia path makes — rather than listing out a subset of fields by hand. A prior version hand-listed the fields, and that list omitted `draft_token` and `has_testimony`. Without those two fields, the mobile client could not match a draft to its identity, and let an operator enable Approve on a draft the server would have refused. Reusing `#to_sway_json` closes that gap by construction: it cannot omit a field the Inertia path also needs.

## Why there's no alba resource here

Sway's usual rule is that new serialization goes through an alba resource (see CLAUDE.md).

This action does not follow that rule yet, because no `BillLlmProvisioningResource` exists. Building one just for this one action would create a third serialization shape for the same object graph — the Inertia path's shape, this action's new resource, and whatever the next caller invents. Matching the existing `#to_sway_json` serializer avoids that split. Migrating the whole object to an alba resource is separate, follow-up work.
