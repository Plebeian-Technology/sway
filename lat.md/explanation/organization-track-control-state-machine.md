---
lat:
  mode: explanation
---

# OrganizationFollowControl.tsx design notes

Follow/unfollow control for civic organizations.

What renders in each state:

| State | Renders |
|---|---|
| signed-out | nothing |
| not following | "Follow" button (primary) → `POST /organization_follows` |
| following, non-member | "Following" badge + "Following" button (outline) → `DELETE` |
| following, member | "Following · member" badge + "Preferences" button (no Unfollow button) |
| muted member | "Muted · member" badge + "Preferences" button |

The member state is decided purely by the `isMember` prop — a member never sees an Unfollow button, regardless of any follow row. A member who has no follow row yet (`followId` absent) still shows "Following · member" plus "Preferences". Clicking Preferences in that case opens the picker in create-on-save mode, so saving preferences creates the follow row.

All the mutations here use Inertia's `useForm` with its post/redirect/get flow — no fetch or axios calls.

## Why the preferences-picker's open/closed state lives above the follow/unfollow branch

The picker's open/closed state lives at the top of this component (not inside the follow/unfollow child components) so it survives the prop change that happens right after following.

The picker's open/closed state lives at the top of this component (not inside the follow/unfollow child components) so it survives the prop change that happens right after following: `FollowForm` unmounts and `UnfollowControl` mounts once Inertia's post/redirect/get flow reloads the page with the real `followId`. The picker opens directly inside the follow POST's `onSuccess` callback — Inertia waits for the reloaded props (with the real `followId`) to arrive before calling `onSuccess` — and the picker is only ever rendered inside the `followId` branch below, so it can never open with a stale or missing id. No extra effect is needed to wait for the id to show up.

`FollowForm`'s `follow()` handler passes `onFollowSuccess` as `onSuccess` for the same reason: by the time `onSuccess` fires, Inertia has already delivered the reloaded page props (including the real `followId`), which avoids ever sending a PATCH with `followId=0`.

## IProps fields

Interface properties driving the follow control state machine, including current membership status and saved preferences.

- `isMember` — true when the signed-in user is an active member of this
  organization. Derived from `is_member_of_org_ids.includes(org.id)` on
  the parent page. Always renders "Following · member" when true — never
  an Unfollow button.
- `isMuted` — true when the member has turned off every notification
  event type (a muted state).
- `isSignedIn` — true when a user session exists. Gates whether this
  control renders at all.
- `followPrefs` — per-follow notification preferences, from
  `user_follow_prefs[org.id]`. Seeds the picker when editing an existing
  follow.
- `orgDefaults` — the user's global default preferences, from
  `current_user_org_defaults`. Seeds the picker on a first follow, and
  for a member who has no follow row yet.

## Why the picker's initial values are seeded the way they are

Seeding the notification preference picker from existing follow records or global defaults avoids reset discrepancies on save.

- Editing an existing follow: seed from `followPrefs` (the saved state).
- A first follow, or a member with no follow row yet: seed from
  `orgDefaults` (the user's global defaults).

For the member-with-no-row case, `followPrefs` is absent, so `followPrefs ?? orgDefaults` falls through to `orgDefaults` automatically.

A member with no follow row yet gets the picker in create-on-save mode (POST instead of PATCH). It seeds from `orgDefaults`, the same values the backend uses when it creates the row. The member branch only seeds from `orgDefaults` when there's no follow row yet (`followPrefs` is absent in that case anyway).
