---
mode: explanation
summary: "Why every OrganizationBillPositionsController action is admin-only, including reads: it exposes unapproved draft positions that public and mobile surfaces deliberately never see."
status: agent-extracted
related: []
---

<!-- vale Vale.Spelling = NO -->

# Why `OrganizationBillPositionsController` is admin-only, reads included

Every action on this controller is admin-only, including reads. Its
endpoints return positions that nobody has approved yet — drafts the
legislation pipeline created with `active: false`, which the public bill
pages deliberately hide.

Nothing outside the admin screens needs this data: web pages receive
positions as Inertia props, and the mobile app reads
`/public/organizations/:id` instead — that public read path is
`Public::OrganizationsController#show`, which returns active positions
only.

## Where the stance-value mapping lives

Turning the stance value clients send into the older `"support"` column
value happens in one place, `OrganizationBillPosition.normalize_support`.
This controller and `BillsController#approve_org_position` both call it,
so the mapping is never written down twice.
