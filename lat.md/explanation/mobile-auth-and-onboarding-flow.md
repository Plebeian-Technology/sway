---
lat:
  mode: explanation
---

# Mobile auth and onboarding flow

How mobile's AuthStack, OnboardingStack, and RootNavigator fit together around a single AuthScreen, and where a newly registered user lands.

## RootNavigator

`RootNavigator` (`mobile/src/navigation/RootNavigator.tsx`) decides what the app shows: the main drawer or the sign-in screens.

It reads `useSession`, so signing in, signing out, or the server rejecting our token all swap the visible screens straight away. An earlier version was told once at launch whether the user was signed in, which was right at launch and wrong ever after.

Signed-out people see the sign-in screens. Signed-in people see onboarding until their registration is complete, and the main drawer after that.

Until the saved session has been read out of the phone's keychain, [[mobile/src/screens/LoadingScreen.tsx#LoadingScreen]] shows the Sway logo and a spinner on the page background. Otherwise the sign-in screen would flash up for a moment on every launch, even for someone already signed in.

For a signed-in person, the loading screen also shows while their first profile loads, and only while there is no user yet. Later profile refetches keep the app mounted and update screens in place, so returning from the background, polling or pull to refresh never drops the reader back on the landing screen. A load that finishes with no user shows a "We could not load your account" screen with a "Try again" button that refetches the profile, and the loading screen replaces it while the refetch runs.

Onboarding is only for a user whose profile loaded and says registration is incomplete. Without the retry screen, a person who finished sign-up long ago and signs in on a new phone during a brief outage would hold no cached profile, receive the signed-out payload with no user, and land on the address form meant for brand-new users.

## AuthStack

`AuthStack` (`mobile/src/navigation/AuthStack.tsx`) is the sign-in flow, which is only two screens:

- `Auth` — everything happens here (`AuthScreen.tsx`)
- `DeviceUnsupported` — the dead end for a phone that cannot use passkeys

Signing in used to be a march through six screens. It is one now.

`RootNavigator` shows this stack whenever nobody is signed in. Once sign-in succeeds, the passkey code announces `signed_in` and `RootNavigator` switches to the main drawer, so no screen in here ever has to navigate its own way out. Because the app drawer is not mounted during sign-in, [[mobile/src/navigation/AuthStack.tsx#AuthStack]] guards all four `SafeAreaView` edges (`top`, `bottom`, `left`, `right`) to keep content clear of both the top notch and the home indicator.

Keeping the list of route names down to `{ Auth, DeviceUnsupported }` is what makes TypeScript reject any attempt to navigate to one of the screens that no longer exists.

### types.ts's AuthStackParamList

The sign-in stack was collapsed down to two screens:

- `Auth` — one screen doing the job of the web passkey panel
- `DeviceUnsupported` — dead end for devices that cannot use passkeys

Keeping this list short acts as a tripwire at compile time: TypeScript rejects any `nav.navigate` call aimed at a route that was deleted (`SignIn`, `PhoneEntry`, `PasskeyAuth`, `SmsFallback`, `SwayRegistration`) or that lives in a different stack (`BillOfTheMonth`, `AppDrawer`, and so on).

## AuthScreen

`AuthScreen` (`mobile/src/screens/AuthScreen.tsx`) is one screen that handles both signing in and signing up.

It replaces a five-screen funnel (SignIn → PhoneEntry → PasskeyAuth → SmsFallback → SwayRegistration) with a single screen that shows different things depending on its state, following the same states as the web passkey panel (`app/frontend/components/auth/PasskeyPanel.tsx`).

The states are tracked as separate booleans, exactly as on the web:

- `isConfirmingPhone=false` → phone box plus a "Continue with Phone" button
- `isConfirmingPhone=true` → code box plus "Confirm code" and "Cancel"
  buttons
- `isLoading=true` → a "Working on it" panel

What happens when something goes wrong:

- the device cannot do passkeys → go to the `DeviceUnsupported` dead end
- no passkey found for that phone → send an SMS code first, and only then
  switch to the code box
- sending the SMS code fails → show the prepared `requestCodeError` message (never the raw API error string) and leave the code box hidden
- anything else → show the error text on the screen

Returning users also get a one-tap discoverable passkey button (`signInDiscoverable`) above the phone field when `isConfirmingPhone` is false; if the user cancels or has no synced passkey (`NoPasskeyError`), nothing is shown and the phone form remains ready. On mobile, the primary submit button sits above the secondary Cancel / Preview Sway button, and the three hero feature cards stack vertically rather than in three columns.

### Held SMS-verified token

After the code is accepted, AuthScreen keeps the returned `sms_verified_token` in a ref until the passkey step succeeds, the server calls it invalid, or the user taps Cancel.

Twilio approves a code once, so a second code check with the same digits answers invalid_code and tells the user a correct code is wrong. The server only peeks at the token when it mints the passkey challenge and consumes it on a successful callback, so a cancelled or failed enrollment can reuse the same token for up to 10 minutes. A press of Confirm code with a held token skips the code check and goes straight to the passkey sheet. An `invalid_sms_token` answer means the token expired, so the ref is emptied and the next press checks the code again.

### Why "Preview Sway" opens a browser instead of navigating

The "Preview Sway" button opens a web URL with `Linking.openURL` instead of navigating inside the app.

`RootNavigator` only mounts the auth stack while nobody is signed in, so the app drawer — which holds the Bill of the Month screen — is not mounted alongside it; navigating to `"BillOfTheMonth"` would compile but land on no route at runtime. Opening the public URL gives the same full page load the web link does. This is a deliberate mobile/web difference, tagged `[platform]`.

## DeviceUnsupportedScreen

`DeviceUnsupportedScreen` (`mobile/src/screens/DeviceUnsupportedScreen.tsx`) is the dead end for devices that cannot use passkeys.

The user arrives here when `passkeyAuth.signIn` throws `PasskeyUnsupportedError`. In Sway a passkey is the only way to sign in: there is no SMS fallback and no SMS recovery. A device without passkey support cannot use Sway at all. This screen says so plainly and points the user at updating their operating system or trying a device that does support passkeys.

This is not the same as a device that supports passkeys but has none enrolled for this account. That case means a new account and leads to registration; this one leads nowhere.

The screen is built from the shared Card and Pressable components, its wording lives in `PARITY_COPY.auth.deviceUnsupported.*`, and its button goes back to the Auth screen.

## OnboardingStack

`OnboardingStack` (`mobile/src/navigation/OnboardingStack.tsx`) is the one step a brand-new user must finish before reaching the app: giving us their address.

People arrive here signed in but with no address on file, because signing up in `AuthScreen` creates a passkey and a session and nothing else. They stay here until the address is saved and the server has matched it to their districts and sent that back in the startup payload. `RootNavigator` watches for the address to appear and then switches to the main drawer.

It reuses `AddressScreen`: same form, same POST to `/sway_registration`. That screen calls `goBack()` after saving, which does nothing here because there is no screen to go back to. That is fine and intended — what moves the user on is the address appearing in the data, not any navigation. Like [[mobile/src/navigation/AuthStack.tsx#AuthStack]], [[mobile/src/navigation/OnboardingStack.tsx#OnboardingStack]] renders outside the app drawer and guards all four `SafeAreaView` edges.

Still to do: wording written for a first-time user, something like "Welcome — let's find your legislators", in place of the current "Updating your address re-checks…". The existing wording is accurate enough for now.

### types.ts's OnboardingStackParamList

The onboarding stack sits between creating a passkey and reaching the app.

A just-registered user has a passkey and a session but no address yet, so no district either. `RootNavigator` keeps them in this stack until an address is saved; once `user.address` has a value the navigator switches to the app drawer.

## AddressScreen

`AddressScreen` (`mobile/src/screens/AddressScreen.tsx`) is where the user enters or changes their address.

Saving makes the server work out the user's district and legislators again (`SwayRegistrationService`). The app only sends the fields; the Rails controller does the geocoding and links up the legislators.

Endpoint: `POST /sway_registration`.

The main path is one Google Places autocomplete box. Whether it is available depends on the platform: `hasGooglePlacesKey` looks up the iOS or Android key from `app.config.ts`. Picking a suggestion fills the parsed pieces (including `latitude` and `longitude`) into the form underneath and shows a selected-address preview card so the user can check it before tapping the submit button. The server accepts the address as a fact and does not need coordinates, so typing an address by hand posts the typed fields with `latitude` and `longitude` null. The submit button is enabled once the street is non-empty, or once a picked suggestion supplied coordinates even with an empty street, and is never blocked for any other missing field. In edit mode it also stays disabled while the form still matches the saved address and no suggestion was picked, because the server treats such a post as a new address and runs a full address switch: it deactivates links, records an address change and starts the cooldown. Editing any field clears the coordinates and the place types, so edited text is never posted with the location or classification of an earlier suggestion. The full set of separate fields is still shown as a fallback when:

- this platform's build has no Google Places API key
- the user taps "Edit address fields" to correct what was parsed

A failed save keeps the form as typed and leaves the submit button usable, so the user can press it again. The error line shows the server's own sentence for a JSON error envelope, such as the address-change cooldown. A request that never reaches the server, including the 15-second timeout, shows a fixed connection sentence, because the platform's abort text (for example `Aborted`) tells the user nothing. An HTML error page shows the client's friendly fallback sentence.

`RootNavigator` and the onboarding stack decide who gets sent here; the `isOnboarding` flag only swaps the wording and the buttons. Onboarding mode reuses the web registration page's wording, edit mode uses mobile-only wording, and the helper block at the bottom carries the same three outside links as the web page.

The two buttons are built from the shared `Pressable` component. Cancel logs the user out during onboarding, or goes back one screen when editing; the web has no counterpart for this. Submit reads "Find My Representatives" during onboarding, or "Save address" when editing.

The helper block matches the divider and three outside links on the web registration page: a note about being a registered voter, then the same three links in the same order. `[platform]`: these open with `Linking.openURL` on mobile, where the web opens a new browser tab.

## Why isOnboarding only changes wording

Onboarding mode means no address has been saved yet.

The button reads "Find My Representatives", and after a successful save the profile refresh moves `RootNavigator` to the app drawer, which opens on Feed. That matches the web app, which sends a newly registered user to `/feed` ([[mobile-tab-navigation-architecture#AppDrawer#The drawer opens on Feed]]). Edit mode (an address already exists) keeps "Save address" and goes back to the profile screens. `RootNavigator` and the onboarding stack already decide the routing, so this flag only changes wording and buttons.
