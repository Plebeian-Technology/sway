---
lat:
  mode: explanation
---

# Mobile organization-follow test notes

Test-setup and behavior rationale from OrgPreferenceSheet.test.tsx and useOrganizationFollow.test.tsx.

## OrgPreferenceSheet.test.tsx and OrgCard

`useOrganizationFollow` does not fetch anything on mount, but following and unfollowing both go through the API client, so the tests stand in a fake one.

Signed-out people are allowed to browse, so "Track" is still on screen even when tapping it opens the sign-in prompt sheet.

## useOrganizationFollow.test.tsx

Test specifications validating optimistic follow toggling, error recovery, and background metadata synchronization on mobile.

### Why follow() never throws when the follow-up GET fails

After a successful `POST /organization_follows`, the hook calls `GET /public/organizations/:id` to learn the real `followId`.

`follow()` must NOT throw when that GET fails; the GET is a best-effort extra. When it fails, `followId` lands on `-1`, meaning "following, id still unknown."

### Why updatePreferences and unfollow throw on the -1 sentinel

`followId` is `-1` when a follow's POST worked but the GET never came back with the id.

`updatePreferences` must throw in that state, so `OrgPreferenceSheet` shows "Couldn't save preferences" instead of pretending the save worked. `unfollow` also throws for the `-1` sentinel and sends no DELETE: `followId` must not flip to `null` in that case, or the app and the server would disagree about whether the user is still following.
