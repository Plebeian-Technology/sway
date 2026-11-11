---
lat:
  mode: reference
---

# NotificationPrefsScreen

`NotificationPrefsScreen` (`mobile/src/screens/NotificationPrefsScreen.tsx`) is everything a user can turn on or off about notifications.

- The top of the screen:

- heading and intro text from `PARITY_COPY.notifications.{title,lead}`
- four switches inside a Card
- each switch's label and description come from
  `PARITY_COPY.notifications.{botmAnnouncement,legislatorVoted,
  voteWindowClosing,orgPositionTaken}`
- `PreferenceToggle` is a `ListRow` with a native `Switch` on it

- The push section has six states. Having permission is not the same thing as being registered with the server:

1. `loading` — the first `getPermissionsAsync()` call is still running
2. `undetermined` — an "Enable push notifications" button
3. `denied` — the denied message plus a "Go to Settings" button
4. `granted-pending-registration` — the user said yes, but the server has
   not confirmed the device push token yet, so the send-test button stays
   HIDDEN
5. `granted-and-registered` — permission given AND the server confirmed;
   "Send test notification" is available
6. `test-sent` / `test-send-error` — what happened after that button was
   pressed

- Below the switches sits an "Organization position updates" card — see [[docs/explanation/org-notification-cascade-and-defaults.md|org-notification-cascade-and-defaults.md]] for what it fetches and the asymmetric on/off cascade.

- A rule this component must keep about push tokens is documented in [[docs/explanation/test-push-device-targeting.md|test-push-device-targeting.md]].

- Styling is NativeWind classes only; no inline style tokens.
