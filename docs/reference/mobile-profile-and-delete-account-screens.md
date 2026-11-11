---
mode: reference
summary: "Layout of ProfileScreen's eight rows and the wording/order DeleteAccountScreen must keep exactly."
status: agent-extracted
related: []
---

# `ProfileScreen` and `DeleteAccountScreen`

## `ProfileScreen`

`ProfileScreen` (`mobile/src/screens/ProfileScreen.tsx`) is the profile
hub. Eight rows, put together from the same items the web drawer shows,
with the theme control sitting inline rather than on its own screen:

1. Address → `AddressScreen`
2. My Memberships → `MembershipsList`
3. Notification Preferences → `NotificationPrefsScreen`
4. Passkey Management → `PasskeyManagementScreen`
5. Theme (Auto / Light / Dark) → changes right here, no navigation
6. Sign Out → `useSession.signOut`
7. Sign Out All Devices (destructive) → confirmation sheet →
   `useSession.signOutAll`
8. Delete Account (destructive) → `DeleteAccountScreen`

Tapping the theme row steps Auto → Light → Dark → Auto through
`useThemeSync`. The text at the right of that row shows the current mode,
taken from `PARITY_COPY.theme.{mode}.label`.

The two destructive rows handled on this screen use the confirmation
sheet directly. Delete Account gets its own screen, so the user has a
moment to read what it means without a sheet sliding off the bottom.

The sheet's wording comes from `PARITY_COPY.profile.account.*`. What the
user reads is handed in through the sheet's body prop; `parityCopy.ts` is
where that fixed wording lives.

Accessibility: every row is a Pressable with a button role and a label.
The theme row's label names both the current mode and the one the next
tap brings.

## `DeleteAccountScreen`

`DeleteAccountScreen` (`mobile/src/screens/DeleteAccountScreen.tsx`) is
the last confirmation step before an account is deleted.

The profile screen sends the user here, to a screen of its own, so they
have time to read what deletion means without a bottom sheet sliding out
of view.

The wording is fixed and must stay word for word:

- Title: "Delete account"
- Body: "This permanently removes your votes, profile, and history. This
  cannot be undone."
- Action: "Delete Account"

When the user confirms:

1. `DELETE /users/:id`, which the Rails default `users#destroy` answers.
   If it comes back 404, show the network error.
2. `useSession.signOut()` wipes the local cache, the secure store, and
   the websocket connection.
3. The `signed_out` event sends `RootNavigator` back to the sign-in
   stack.
