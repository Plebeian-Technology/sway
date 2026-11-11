---
lat:
  mode: reference
---

# useOrganizationFollow hook

`useOrganizationFollow` (`mobile/src/hooks/useOrganizationFollow.ts`) follows an organization, unfollows it, or changes what it notifies you about.

- The screen updates first and the server is told after. If the server refuses, the change is undone. This is the same undo-on-failure discipline `useNotificationPrefs` uses.

- Signing in comes first: never call `follow`, `unfollow` or `updatePreferences` for a signed-out person. A tap while signed out opens the sign-in sheet instead.

- Every change reads the old value into a local variable before touching the screen, then puts it back if the request throws.

## The followId sentinel

`followId`: `null` means not following. `-1` means following, id still unknown. Any number above 0 is the real id.

- One quirk of the server: `POST /organization_follows` answers with `{ redirect, flash }` — the reply a browser would want — rather than the new follow record, so it never tells us the follow's id. After a successful POST, `follow()` therefore fetches `/public/organizations/:id` and reads `current_user_follow_id` from it. If that second request fails, the hook lets it go: `followId` stays at `-1`, a stand-in meaning "you are following, but we do not know the id yet". `updatePreferences` refuses to run while `followId` is `-1`.

## follow()

Reading `followId` directly into `prevId` is safe here: `follow()` runs start to finish as one sequence, with nothing else writing this value alongside it.

- If the follow-up request for the real id fails, it is not worth retrying: the POST worked, so the follow really exists. `followId` is left at `-1`; `updatePreferences` already refuses to run on `-1`.

## unfollow()

`-1` means the follow was created but the id was never learned, so there is nothing to send a DELETE for.

- The screen does not clear in that case — that would show "not following" while the server still says otherwise. `unfollow()` throws instead, so the caller can say "Couldn't unfollow. Try again." This fixes itself the next time the screen loads, because the id comes down with the page data.

## updatePreferences

PATCHes `/organization_follows/:id/preferences`.

- Does nothing, quietly, when `followId` is `null`, because there is
  nothing to change — a member who has never followed the organization
  should call `createFollowWithPrefs` instead. This makes it safe to call
  from anywhere.
- Throws when `followId` is `-1` — following, but the id has not come back
  yet — so the settings sheet can say "Couldn't save preferences" instead
  of claiming a success that never happened.
- Nothing is changed on screen ahead of the server here: the switches
  belong to the settings sheet's own state. A failure is thrown onwards so
  the sheet can show "Couldn't save preferences. Try again."

## createFollowWithPrefs

For someone who is a member of the organization but has never followed it.

- One POST to `/organization_follows` both starts the follow and stores the chosen notification settings, so there is no moment where one exists without the other. The website saves this case the same way. Both `organization_id` and the `organization_follow` settings travel in the same POST, so the follow can never exist without its settings.

- After that POST, the hook asks the organization for the real `follow_id`. If that fails, it settles for the `-1` stand-in.

## @param initialFollowId

The `follow_id` the server already sent in `user_follows[orgId]`; `null` means not following.
