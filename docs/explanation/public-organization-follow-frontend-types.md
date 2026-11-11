---
mode: explanation
summary: "What the public organization and organization-follow TypeScript types in app/frontend/index.d.ts mirror, and why they're shaped the way they are."
status: agent-extracted
related: [docs/explanation/organization-bill-position-ai-summary-flag.md, docs/explanation/organization-follow-notification-design.md]
---
<!-- vale Vale.Spelling = NO -->

# Public organization and follow types (`app/frontend/index.d.ts`)

## `IPublicOrganization`

The public, non-admin organization browse and detail pages, served by
`Public::OrganizationsController`. This matches the pared-down
`Organization#to_public_json` and `OrganizationBillPosition#to_public_json`
payloads, NOT the admin `IOrganization` shape, so it deliberately leaves
out fields meant only for the server and adds the `sway_locale_slug` the
public pages display. The follow-related fields came later.

## Props for following an organization

The notification settings for one follow, sent by
`Public::OrganizationsController`. Keyed by `org_id` (a string in JSON, but
`Record<number,…>` still works in TS). Present only when signed in; an
empty `{}` when signed in and following nothing.
