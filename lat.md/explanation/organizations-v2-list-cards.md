---
lat:
  mode: explanation
---

# The current (V2) organizations dashboard cards

What MembershipCard, PendingChangesList, and PositionCard (the current V2 organizations dashboard components) each render and why.

## MembershipCard.tsx, the current (V2) membership summary card

Rendered in the memberships dashboard grid.

Shows the organization's identity (avatar or initials), a role badge, the position count, and a primary button linking to the membership detail page. Position and pending-change counts use tabular-nums lining-nums (a font style where digits all line up in neat columns), per the UI design spec.

## PendingChangesList.tsx, the current (V2) pending-changes list

Wraps `PendingChangeCard` — scrolls to and highlights the incoming `new_position_id` if one is passed down (used by the create-position flow's redirect).

## PositionCard.tsx, the current (V2) position card

Admins can edit inline (a support dropdown plus a summary textarea), with a confirmation step before deleting.

Locked positions show a lock badge with a tooltip, matching how the legacy version gated approved positions. The backend URLs are unchanged from the legacy version.
