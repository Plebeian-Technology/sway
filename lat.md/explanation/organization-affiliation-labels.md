---
lat:
  mode: explanation
---

# Organization affiliation labels

Most organizations on Sway never joined it: Sway compiled their positions from public testimony and news. The labels tell a reader who wrote each position, so no organization appears to act on Sway.

The copy lives in the `orgs` section of [[app/frontend/sway_constants/parityCopy.ts#PARITY_COPY]] so web and mobile show the same words in the same places: the organizations list, an organization's page, its cards, and the organization positions on a bill. Who wrote a position comes from its `source_kind` ([[news-org-position-persistence#Position origin and affiliation]]); whether an organization takes part comes from `managed_on_sway` ([[organizations-controller-notes#OrganizationsController design notes#managed_on_sway: an active member, batched across a list]]).

## Every position carries its own tag

The tag sits on each position, not on the organization, because one organization can hold positions from both sources: a position compiled before members joined keeps its origin after they join.

A position whose `source_kind` is `organization` reads "Posted by {Org}". Every other value, including nil for positions recorded before the origin existed, reads "Compiled by Sway". Unknown origin is treated as compiled because claiming an organization wrote something it may not have written is the error the labels exist to prevent.

Web and mobile both take the tag and the source label from [[app/frontend/sway_utils/organizationPositionLabels.ts#organizationPositionTag]] and [[app/frontend/sway_utils/organizationPositionLabels.ts#organizationPositionSourceLabel]], so the two apps cannot disagree on who wrote a position.

[[app/frontend/components/bill/OrgPositionSummary.tsx#OrgPositionSummary]] renders the tag only when a caller passes the organization name, so a call site that has not been wired yet renders as it did before. It renders the tag even when the position has no summary.

## Organization pages say whether the organization takes part

The organizations list carries one notice under its title: Sway compiles positions from public testimony and news reporting, and an organization is affiliated only when its page says it manages its positions on Sway.

An organization's own page then says one of two things. With an active member it reads "{Org} manages its positions on Sway."; without one it says the organization is not affiliated with Sway and is not responsible for the content. The notice makes no claim about who wrote the positions, because an organization whose members have all left keeps the positions they posted, still tagged "Posted by {Org}". A card in the list shows only the managed label, since the list notice already covers every other organization.

The member's own organization page (the membership page) receives `source_kind` and `source_url` on each position so its cards can tag positions and link their sources the same way.

## A compiled position names its source

A position Sway compiled from hearing testimony or a news article carries a source line, so a reader can check the record Sway relied on instead of taking Sway's word for the organization's stance.

The line reads "Source: hearing testimony" or "Source: news article" and links to `source_url` when one is known and safe, in a new tab on the web and in the system browser on mobile; without a URL it shows the label alone. A position the organization posted, one a Sway admin entered, and one with no recorded origin show no source line, since there is no outside record to point to. Testimony positions carry no URL today ([[news-org-position-persistence#Position origin and affiliation#Values and write paths]]), so they show the label alone.

## Tracking, not following

A reader tracks an organization to hear when Sway records its positions. "Follow" and a follower count read as if the organization had an audience on Sway, so the copy says Track, Tracking and Stop tracking.

The code keeps the follow names (`OrganizationFollow`, `organization_follows`, its routes and props); [[docs/terminology.md]] records the split.

## The bill page carries the notice once

Every bill layout tags each organization position the same way and shows the list page's notice once near its organization positions, only when the bill has any.

A bill with no organization positions shows no notice, since there is nothing for it to explain.
