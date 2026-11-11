---
mode: explanation
summary: "How mobile's AuthStack, OnboardingStack, and RootNavigator fit together around a single AuthScreen, and how the onboarding handoff lands a new user on the Legislators tab."
status: agent-extracted
related: [mobile-tab-navigation-architecture]
---

# Mobile auth and onboarding flow

## `RootNavigator`

`RootNavigator` (`mobile/src/navigation/RootNavigator.tsx`) decides what
the app shows: the main tabs or the sign-in screens.

It reads `useSession`, so signing in, signing out, or the server rejecting
our token all swap the visible screens straight away. An earlier version
was told once at launch whether the user was signed in, which was right at
launch and wrong ever after.

Signing in is not required to look around: the main tabs are shown to
signed-out people too, so they can read public bills and legislators. The
sign-in screens appear only when someone taps Sign in, or when the server
rejects our token and forces the switch.

Nothing is drawn until the saved session has been read out of the phone's
keychain. Otherwise the sign-in screen would flash up for a moment on
every launch, even for someone already signed in.

## `AuthStack`

`AuthStack` (`mobile/src/navigation/AuthStack.tsx`) is the sign-in flow,
which is only two screens:

- `Auth` — everything happens here (`AuthScreen.tsx`)
- `DeviceUnsupported` — the dead end for a phone that cannot use passkeys

Signing in used to be a march through six screens. It is one now.

`RootNavigator` shows this stack whenever nobody is signed in. Once
sign-in succeeds, the passkey code announces `signed_in` and
`RootNavigator` switches to the main tabs, so no screen in here ever has
to navigate its own way out.

Keeping the list of route names down to `{ Auth, DeviceUnsupported }` is
what makes TypeScript reject any attempt to navigate to one of the screens
that no longer exists.

### `types.ts`'s `AuthStackParamList`

The sign-in stack was collapsed down to two screens:

- `Auth` — one screen doing the job of the web passkey panel
- `DeviceUnsupported` — dead end for devices that cannot use passkeys

Keeping this list short acts as a tripwire at compile time: TypeScript
rejects any `nav.navigate` call aimed at a route that was deleted
(`SignIn`, `PhoneEntry`, `PasskeyAuth`, `SmsFallback`,
`SwayRegistration`) or that lives in a different stack (`BillOfTheWeek`,
`AppTabs`, and so on).

## `AuthScreen`

`AuthScreen` (`mobile/src/screens/AuthScreen.tsx`) is one screen that
handles both signing in and signing up.

It replaces a five-screen funnel (SignIn → PhoneEntry → PasskeyAuth →
SmsFallback → SwayRegistration) with a single screen that shows different
things depending on its state, following the same states as the web
passkey panel (`app/frontend/components/auth/PasskeyPanel.tsx`).

The states are tracked as separate booleans, exactly as on the web:

- `isConfirmingPhone=false` → phone box plus a "Continue with Phone" button
- `isConfirmingPhone=true` → code box plus "Confirm code" and "Cancel"
  buttons
- `isLoading=true` → a "Working on it" panel

What happens when something goes wrong:

- the device cannot do passkeys → go to the `DeviceUnsupported` dead end
- no passkey found for that phone → send an SMS code first, and only then
  switch to the code box
- sending the SMS code fails → show the error and leave the code box
  hidden
- anything else → show the error text on the screen

### Why "Preview Sway" opens a browser instead of navigating

The "Preview Sway" button opens a web URL with `Linking.openURL` instead
of navigating inside the app. `RootNavigator` only mounts the auth stack
while nobody is signed in, so the app tabs — which hold the Bill of the
Week screen — are not mounted alongside it; navigating to
`"BillOfTheWeek"` would compile but land on no route at runtime. Opening
the public URL gives the same full page load the web link does. This is a
deliberate mobile/web difference, tagged `[platform]`.

## `DeviceUnsupportedScreen`

`DeviceUnsupportedScreen` (`mobile/src/screens/DeviceUnsupportedScreen.tsx`)
is the dead end for devices that cannot use passkeys.

The user arrives here when `passkeyAuth.signIn` throws
`PasskeyUnsupportedError`. In Sway a passkey is the only way to sign in:
there is no SMS fallback and no SMS recovery. A device without passkey
support cannot use Sway at all. This screen says so plainly and points the
user at updating their operating system or trying a device that does
support passkeys.

This is not the same as a device that supports passkeys but has none
enrolled for this account. That case means a new account and leads to
registration; this one leads nowhere.

The screen is built from the shared Card and Pressable components, its
wording lives in `PARITY_COPY.auth.deviceUnsupported.*`, and its button
goes back to the Auth screen.

## `OnboardingStack`

`OnboardingStack` (`mobile/src/navigation/OnboardingStack.tsx`) is the one
step a brand-new user must finish before reaching the app: giving us their
address.

People arrive here signed in but with no address on file, because signing
up in `AuthScreen` creates a passkey and a session and nothing else. They stay here until the address is saved and the server has
matched it to their districts and sent that back in the startup payload.
`RootNavigator` watches for the address to appear and then switches to
the main tabs.

It reuses `AddressScreen`: same form, same POST to `/sway_registration`.
That screen calls `goBack()` after saving, which does nothing here because
there is no screen to go back to. That is fine and intended — what moves
the user on is the address appearing in the data, not any navigation.

Still to do: wording written for a first-time user, something like
"Welcome — let's find your legislators", in place of the current "Updating
your address re-checks…". The existing wording is accurate enough for
now.

### `types.ts`'s `OnboardingStackParamList`

The onboarding stack sits between creating a passkey and reaching the app.
A just-registered user has a passkey and a session but no address yet, so
no district either. `RootNavigator` keeps them in this stack until an
address is saved; once `user.address` has a value the navigator switches
to the app tabs.

## `onboardingHandoff`

A single note passed from the sign-up screens to the main tabs, read once
and then thrown away (`mobile/src/navigation/onboardingHandoff.ts`).

When someone finishes entering their address, the tabs should open on
Legislators rather than Home, so the first thing they see is the
representatives the server just found for that address. Every launch
after that should start on Home as usual.

This is a plain variable in a module rather than React state, because the
address screen is taken down before the tabs are built, so there is no
shared React state to pass it through. A module keeps its value across
that swap.

### `AppTabs`'s use of the handoff flag

Someone who has just finished signing up lands on the Legislators tab, so
the first thing they see is the representatives found from their address.
This is worked out once, when the tabs are first built: React keeps the
answer through later renders, and reading the flag also clears it, so the
next launch starts on Home as usual.

## `AddressScreen`

`AddressScreen` (`mobile/src/screens/AddressScreen.tsx`) is where the
user enters or changes their address.

Saving makes the server work out the user's district and legislators
again (`SwayRegistrationService`). The app only sends the fields; the
Rails controller does the geocoding and links up the legislators.

Endpoint: `POST /sway_registration`.

The main path is one Google Places autocomplete box. Whether it is
available depends on the platform: `hasGooglePlacesKey` looks up the iOS
or Android key from `app.config.ts`. Picking a suggestion fills the
parsed pieces into the form underneath. The full set of separate fields is
still shown as a fallback when:

- this platform's build has no Google Places API key
- the user taps "Edit address fields" to correct what was parsed

`RootNavigator` and the onboarding stack decide who gets sent here; the
`isOnboarding` flag only swaps the wording and the buttons. Onboarding
mode reuses the web registration page's wording, edit mode uses
mobile-only wording, and the helper block at the bottom carries the same
three outside links as the web page.

The two buttons are built from the shared `Pressable` component. Cancel
logs the user out during onboarding, or goes back one screen when
editing; the web has no counterpart for this. Submit reads "Find My
Representatives" during onboarding, or "Save address" when editing.

The helper block matches the divider and three outside links on the web
registration page: a note about being a registered voter, then the same
three links in the same order. `[platform]`: these open with
`Linking.openURL` on mobile, where the web opens a new browser tab.

### Why `isOnboarding` only changes wording

Onboarding mode means no address has been saved yet. The button reads
"Find My Representatives", and after a successful save the app tabs open
on the Legislators tab. Edit mode (an address already exists) keeps "Save
address" and goes back to the profile screens. `RootNavigator` and the
onboarding stack already decide the routing, so this flag only changes
wording and buttons.

### Why the handoff flag is set before refreshing

Set the handoff flag BEFORE refreshing, so the tabs can read it the very
first time they render. The chain is: refresh → the user now has an
address → `RootNavigator` swaps stacks → the tabs mount → they read and
clear the flag → they open on Legislators. The web app likewise sends you
to the legislators page after a successful save.
