---
lat:
  mode: reference
---

# OrgDetailScreen

`OrgDetailScreen` (`mobile/src/screens/OrgDetailScreen.tsx`) is one organization's page. The web has nothing matching it, so mobile decides the layout. `[no-web-counterpart]`

- What is on it:

- a follow control in the header (`testID="org-detail-header"`)
- a preferences sheet, opened by the Preferences button

- There is no sign-in prompt sheet here, because `OrgDetailFollowSection` is only mounted for a signed-in user. One used to sit here that could never open, and it was removed rather than left as a trap if that signed-in check is ever loosened.

- Membership: `isMember` comes from the `is_member_of_org_ids` prop. A member sees "Member" plus Preferences, with no unfollow button and no follow id required. Signed-out people can still browse: the server leaves the follow props out entirely when nobody is signed in.

- Layout:

- `testID="org-detail-header"`: name, locale slug, follow control, follower
  count
- `testID="org-detail-positions"`: the positions list, read only

## OrgDetailPayload's follow-preference fields

`user_follow_prefs` — notification settings per organization, keyed by organization id.

- This endpoint sends at most one entry — the organization being viewed — or `{}` when the user does not follow it. It gives `OrgPreferenceSheet` its opening values for someone who already follows.

## Why OrgDetailFollowSection is its own component

`useOrganizationFollow` has to start with the real follow id from the loaded data.

- If that state were set up in the parent, `useState` would capture the null from the loading render and never pick up the real value once the data arrived. `OrgDetailFollowSection` is mounted only once the data has loaded, so `useOrganizationFollow` starts with the real follow id instead of the null it would see while loading. `useState` keeps whatever value it was handed on the first render, so getting that first value right is what matters.

## The notification-settings sheet

`initialPrefs` holds the real saved settings for an existing follower, or the user's global defaults for a member with no follow record.

- `onSave` creates the follow record along with the settings when the user is a member without one. There is no sign-in prompt sheet: this whole section only mounts for a signed-in user, so a signed-out state can never be reached here. The key changes on each open, so the sheet is rebuilt and reads `initialPrefs` again, with no effect watching whether it is visible.

## Why the follow section is keyed on the server-assigned follow id

Key this on the follow id the SERVER gave us.

- If following worked but the follow-up read failed, the id is left as the `-1` placeholder; when a pull-to-refresh later brings back a real id, this key changes, the section is rebuilt, and `useOrganizationFollow` starts again from that real id. It clears the stuck placeholder without an effect trying to reconcile it.
