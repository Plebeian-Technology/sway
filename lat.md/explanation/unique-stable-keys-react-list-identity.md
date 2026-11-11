---
lat:
  mode: explanation
---

# Why uniqueStableKeys always appends an occurrence number

`app/frontend/sway_utils/uniqueStableKeys.ts` builds React keys for a list whose entries can be removed from the middle, and whose child components keep their own state started from props.

Keying such a list on the position in the array is the bug: removing one entry renumbers every entry after it, so their keys change, React tears those components down and builds them again, and whatever the admin had typed is thrown away without a word. The key has to come from the entry itself.

That identity is not always unique — two identical draft org positions boil down to the same `draft_token` (see [[docs/explanation/draft-org-position-identity.md|draft-org-position-identity.md]]) — and a repeated key makes React match both children against the first one it finds. So every entry also carries a number saying which occurrence it is. That number shifts if an identical twin is removed, which is the one case left where typing can be lost; entries sharing an identity look exactly alike on screen, so there is nothing to choose between them.

## Why the occurrence number goes on every entry, not just repeats

The number goes on EVERY entry, including the first.

It used to go only on repeats, which put it in the same space as the identities it was meant to tell apart: a second "A" became "A#1", and so did a lone entry whose identity IS the text "A#1". The helper that exists to prevent duplicate keys could create one, and that was reachable: `draftOrgPositionKeys` falls back to `${org_name} ${stance} ${summary}`, and "#1" is ordinary English.

Always adding the number means every (identity, occurrence) pair maps to its own key by construction: a key is the identity, one "#", then digits, so splitting at the LAST "#" recovers both halves whatever the identity contains. That is a one-line argument a reader can check, which is why it beats escaping "#" inside the identity — that also works, but only by reasoning about runs of "#".

## The identities parameter

One identity per entry, taken from the entry's content or from the server, in the order they render. Must not come from the entry's position in the array.

## draftOrgPositionKeys

React keys used to be org name + array index, shifting on every Approve/Reject (delete-then-reload) and losing unsaved edits. `draft_token` is a stable, content-derived id instead. See [[docs/explanation/draft-org-position-identity.md|draft-org-position-identity.md]] for how `draft_token` itself is computed.
