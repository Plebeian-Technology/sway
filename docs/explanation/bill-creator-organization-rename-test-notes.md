---
mode: explanation
summary: "Why BillCreatorOrganizationRename.test.tsx hand-writes the new name into the form and guards against treating a refused rename as applied."
status: agent-extracted
related: []
---

# BillCreatorOrganizationRename test notes

Renaming hand-writes the new name into the form, since the redirect that follows
doesn't refresh the form's own copy — but must not do so when the write was refused.

A stale page token redirects back to the same page, which Inertia treats as an
ordinary successful visit — same onSuccess as a real save — so a refused rename
would otherwise look applied.

## The name box stays open on a refused rename

Nothing was saved, so nothing may be written into the form. The name
box stays open on the old name rather than closing over a rename that
did not happen.

(`app/frontend/components/admin/creator/__tests__/BillCreatorOrganizationRename.test.tsx`)
