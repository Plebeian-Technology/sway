---
lat:
  mode: explanation
---

# Organization affiliation labels

Most organizations on Sway never joined it: Sway compiled their positions from public testimony and news. The labels tell a reader who wrote each position, so no organization appears to act on Sway.

The copy lives in the `orgs` section of [[app/frontend/sway_constants/parityCopy.ts#PARITY_COPY]] so web and mobile show the same words. Who wrote a position comes from its `source_kind` ([[news-org-position-persistence#Position origin and affiliation]]); whether an organization takes part comes from `managed_on_sway` ([[organizations-controller-notes#OrganizationsController design notes#managed_on_sway: an active member, batched across a list]]).

## Every position carries its own tag

The tag sits on each position, not on the organization, because one organization can hold positions from both sources: a position compiled before members joined keeps its origin after they join.

A position whose `source_kind` is `organization` reads "Posted by {Org}". Every other value, including nil for positions recorded before the origin existed, reads "Compiled by Sway". Unknown origin is treated as compiled because claiming an organization wrote something it may not have written is the error the labels exist to prevent.

[[app/frontend/components/bill/OrgPositionSummary.tsx#OrgPositionSummary]] renders the tag only when a caller passes the organization name, so a call site that has not been wired yet renders as it did before. It renders the tag even when the position has no summary.

## Organization pages say whether the organization takes part

The organizations list carries one notice under its title: Sway compiles positions from public testimony and news reporting, and an organization is affiliated only when its page says it manages its positions on Sway.

An organization's own page then says one of two things. With an active member it reads "{Org} manages its positions on Sway."; without one it says the organization is not affiliated with Sway, is not responsible for the content, and that Sway compiled the positions. A card in the list shows only the managed label, since the list notice already covers every other organization.

The member's own organization page (the membership page) receives `source_kind` on each position so its cards can tag positions the same way.
