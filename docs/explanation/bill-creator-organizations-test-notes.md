---
mode: explanation
summary: "Test-setup rationale for BillCreatorOrganizations.test.tsx: the temporary-id scheme for inline-created organizations, and why useForm is stood in with a React.useState-backed version."
status: agent-extracted
related: []
---

# BillCreatorOrganizations test notes

## Removed-row temporary ids must not be reused

Each inline-created org needs a distinct temporary id; a removed row must be
remembered at removal time, not via an effect mirroring the selection into a ref.

The old id scheme, `-(selected.length + 1)`, let a removed row's negative id get
reused by the next created org, silently replacing it.

## The picker and chips run for real; only useForm is a stand-in

The real picker and chips run for real; only useForm is replaced with a
React.useState-backed version so setData actually redraws the parent.

## React keys must not shift when an earlier row is removed

React keys include a shifting index, so removing an earlier row changes later keys, remounts those
children, and silently discards any in-progress rename.

`organization.value` is already a unique, unchanging id from the server. The
`-${index}` on the end is the entire defect.

(`app/frontend/components/admin/creator/__tests__/BillCreatorOrganizations.test.tsx`)
