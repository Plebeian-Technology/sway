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

- Styling is NativeWind classes only; no inline style tokens. The one inline style is the footer's bottom padding, which comes from the safe-area inset.

## Save feedback and pinned footer

The "Save preferences" button for the organization defaults card is pinned in a footer below the scroll view, so it needs no scrolling to find and always shows what the last save did.

- The footer (`notification-prefs-footer`) is a sibling of the scroll view, padded by the larger of the bottom safe-area inset and 12pt.
- The form state lives in `useOrgDefaultsForm`; the card only renders the fields, and the footer owns the button.
- While the PATCH is in flight, while the defaults are still loading, or after they failed to load, the button is disabled with `busy` set and reads "Saving…"; a ref also blocks a second request.
- Success shows `PARITY_COPY.notifications.saved` (the web flash wording) in a polite live region, announces it with `AccessibilityInfo`, and clears after four seconds or on the next edit.
- Failure shows an alert in the footer and keeps every chosen value so the user can retry. A 4xx `ApiRequestError` message is shown as is; a network, 5xx or bare "HTTP nnn" message falls back to `PARITY_COPY.notifications.saveError`.
