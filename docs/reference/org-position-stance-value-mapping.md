---
mode: reference
summary: "Documents how wire-format organization stance values map to legacy storage values, and which service owns organization-position approval logic."
status: agent-extracted
related: []
---

# Organization position stance mapping and service ownership

## Stance value mapping

`POST /bills/:id/approve_org_position` accepts wire-format `stance` values,
defined in `config/schemas/bill_positions.json`. These map to the legacy
values the database stores:

| Wire value | Stored value |
|---|---|
| `support` | `FOR` |
| `oppose` | `AGAINST` |
| `neutral` | `ABSTAIN` |

`OrganizationBillPosition.normalize_support` performs this mapping. Both
`BillsController` and `OrganizationBillPositionsController` call it, so the
two controllers cannot disagree about what a stance value means.

## What ApproveOrgPositionService owns

`ApproveOrgPositionService` owns the full approval operation:

- Validates the request (organization name, stance, summary).
- Finds a fuzzy-matched organization, or creates one when no close match
  exists.
- Upserts the position with `find_or_initialize_by` + `save!`. Upsert, not
  plain create, means a second Approve click — sent after the operator edits
  the draft — updates the existing position instead of silently dropping the
  edit.
- Removes the approved draft from the bill's pending draft list.
- Writes the audit-log entry.

`BillsController#approve_org_position` only maps the service's outcome to a
redirect. It does none of the above itself.
