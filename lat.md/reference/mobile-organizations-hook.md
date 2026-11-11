---
lat:
  mode: reference
---

# useOrganizations hook

`useOrganizations` (`mobile/src/hooks/useOrganizations.ts`) loads `/public/organizations`, optionally narrowed to one place.

- Along with the organizations themselves, the response carries who the reader follows:

- `follower_count` on each organization
- `user_follows`, a lookup of organization id → follow id
- `is_member_of_org_ids`, the organizations this person actually belongs to

- The last two appear only when the request carries a login token. Signed-out people can still browse the list; they simply get neither.

- `is_member_of_org_ids` is the only source of truth for membership. Never work membership out from `user_follows`: someone can be a member without following, so the two lists do not match.

## Payload fields

Attribute definitions and types returned in the mobile organization subscription response payload.

- `OrganizationRecord.follower_count` — how many people follow this
  organization. The server always sends it.
- `OrgFollowPref` — what this person asked to be told about, for one
  organization they follow. These arrive in `user_follow_prefs`, and only
  for organizations they actually follow.
- `OrgFollowPref.muted` — true when all three `notify_on_*` switches are
  off. Drives the "Muted · member" badge.
- `OrgDefaultPrefs` — the person's own default answer for every
  organization, stored on their user record as `notify_on_*_default` and
  `org_position_cadence_default`. These fill in the settings sheet for a
  member who does not follow the organization yet.
- `OrganizationsPayload.user_follows` — a lookup of organization id →
  follow id for the signed-in person. The server sends it only when the
  request carries a login token. For a signed-out reader the field is
  missing entirely — not an empty object.
- `OrganizationsPayload.is_member_of_org_ids` — the ids of organizations
  this person is currently a member of. Sent only when the request carries
  a login token. This is the only place membership comes from. Someone can
  be an active member without following, so `user_follows` cannot tell you
  who is a member.
- `OrganizationsPayload.user_follow_prefs` — notification settings per
  followed organization, keyed by organization id. Sent only to a
  signed-in reader. It is an empty object for someone signed in who
  follows nothing. `OrgCard` and `OrgDetailScreen` use it to fill in the
  settings sheet.
- `OrganizationsPayload.current_user_org_defaults` — the person's own
  default notification answers for organizations. Sent whenever they are
  signed in. It fills in the settings sheet for a member who does not
  follow the organization yet.
