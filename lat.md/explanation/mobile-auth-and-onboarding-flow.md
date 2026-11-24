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

### A link that arrives before the main screens is kept

A link tapped while the person is signed out or still onboarding opens its screen once the main drawer shows.

The sign-in and onboarding stacks hold none of the screens a link names, so React Navigation finds nowhere to go and lets the link fall. [[mobile/src/navigation/pendingDeepLink.ts#subscribeToLinks]] is the link subscription the navigation container uses: it passes every link on as before, and remembers the most recent one that came in while the drawer was not showing. [[mobile/src/navigation/pendingDeepLink.ts#usePendingDeepLink]], called by `RootNavigator`, hands the remembered link back to React Navigation's own link handler when the drawer mounts, so a kept link takes the same path as a fresh one.

The link that launched the app needs none of this. The navigation container already holds a launch link until a navigator that knows its screen mounts.

Signing out forgets the kept link. Otherwise a link tapped by one person would open for the next person to sign in on the same phone.

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
- the first code never arrives → the code box offers "Send a new code", which requests another code for the same phone, clears the code field and any held SMS-verified token (so the next Confirm checks the new code instead of sending the old token) and confirms with `codeResent`; the button waits out the cooldown clock described in [[phone-verification-rate-limits#Why one phone gets one code a minute and ten a day#The cooldown clock on Send a new code]]; a 429 starts that clock from its `Retry-After`, and any other refused resend shows `requestCodeError` and keeps the code box open
- the first code is refused with a 429, whatever its wait, and this screen already sent a code to the same phone → that code may still be valid, so the code box opens with the resend clock set from `Retry-After`, even when the wait is the daily one; without such an earlier send the server may have kept the cooldown after a failed delivery, so the phone form names the wait through `resendCodeWait` instead of `requestCodeError`
- the first code is refused with 422 `invalid_phone` → the phone form shows the server's sentence, falling back to `validationPhone`, instead of "try again"
- phone sign-in is refused with a 429 → the phone form names the wait from `Retry-After` through `signInWait` instead of the generic `signInError`
- anything else → show a prepared message, never the raw error text (see [[mobile-auth-and-onboarding-flow#AuthScreen#Code step failure messages]])

Returning users also get a one-tap discoverable passkey button (`signInDiscoverable`) above the phone field when `isConfirmingPhone` is false; if the user cancels or has no synced passkey (`NoPasskeyError`), nothing is shown and the phone form remains ready. On mobile, the primary submit button sits above the secondary Cancel / Preview Sway button, and the three hero feature cards stack vertically rather than in three columns.

### Held SMS-verified token

After the code is accepted, AuthScreen keeps the returned `sms_verified_token` in a ref until the passkey step succeeds, the server calls it invalid, a new code is sent, or the user taps Cancel.

Twilio approves a code once, so a second code check with the same digits answers invalid_code and tells the user a correct code is wrong. The server only peeks at the token when it mints the passkey challenge and consumes it on a successful callback, so a cancelled or failed enrollment can reuse the same token for up to 10 minutes. A press of Confirm code with a held token skips the code check and goes straight to the passkey sheet. An `invalid_sms_token` answer means the token expired, so the ref is emptied and the screen returns to the phone form to request a new code.

### Code step failure messages

When Confirm code fails, AuthScreen shows one prepared sentence for the failure class and never the server code or the runtime text.

Mapping from error to outcome:

- a wrong code, a rejected passkey (`invalid_passkey`, `invalid_credentials`), too many attempts (`RateLimitedError`) and no network (`NetworkError`) each get their own sentence under the code box; the held token stays. The too-many-attempts sentence names the wait from `Retry-After` through `attemptsWait`, and falls back to a fixed sentence only when the header is absent
- a cancelled passkey sheet shows `passkeyDismissedMobile`, which names Confirm code and never mentions a browser; the web code step and phone step have their own wording in `passkeyDismissed` and `passkeyDismissedResume`
- a phone with no passkey provider (`PasskeyProviderMissingError`, from the native `NoCreateOption`) shows `passkeyNoProviderAndroid`, the only no-provider sentence, and keeps the held token; iOS never produces `NoCreateOption`, so that message is Android only, and the same error covers, on Android registration only, native `BadConfiguration`
- a 503 `onboarding_unavailable` (the server's onboarding safety net) shows its own sentence, `Something went wrong on our side. Please try again.`, instead of blaming the code, and keeps the held token
- a server error shows the shared `verifyError` copy and keeps the held token; so does an unidentified error from the code check
- an unmapped error thrown during the passkey step, including the native `BadConfiguration` on iOS and errors the library reports only as `UnknownError` or "Native error" (iOS "device not configured", Android `NotConfigured`), shows `passkeyUnidentifiedMobile`, which names a screen lock or passcode and up-to-date software, says to press Confirm code again and, if that still fails, to sign up on another device or at sway.vote, which gives a way forward when the cause is one the user cannot fix; the held token stays. Errors the app identifies, and server or network failures during that step, keep their own sentences
- a create ceremony that throws native `NotSupported` (`PasskeyCreateUnsupportedError`) shows `passkeyCreateUnsupportedAndroid` or `passkeyCreateUnsupportedIos` by platform, which says to update the system software (and Google Play services on Android) and press Confirm code again, then to sign up on another device or at sway.vote if it still fails; the held token stays and the user never reaches `DeviceUnsupported` from the code step
- an expired token (`invalid_sms_token`) and an existing account (`phone_already_registered`) reset like Cancel and return to the phone form, where the message asks for a new code or points at the passkey sign-in button

The sentences for server codes live in `AuthScreen.tsx` because the web passkey panel has no equivalent states. The passkey sentences that differ by client sit in `parityCopy.ts` (`passkeyDismissedMobile`, `passkeyNoProviderAndroid`, `passkeyUnidentifiedMobile` and the `passkeyCreateUnsupported` pair), next to the web wording they replace. Each failure ends on a screen the user can act from: either the code box with the Confirm code button, or the phone form with the passkey button.

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

The main path is one Google Places autocomplete box. Whether it is available depends on the platform: `hasGooglePlacesKey` looks up the iOS or Android key from `app.config.ts`. Picking a suggestion fills the parsed pieces (including `latitude` and `longitude`) into the form underneath and shows a selected-address preview card so the user can check it before tapping the submit button. The server accepts the address as a fact and does not need coordinates, so typing an address by hand posts the typed fields with `latitude` and `longitude` null. The street line and the apartment are posted separately as `street` and `street2` (null when blank), never joined, because the server folds `street2` into the address key and joining would merge every apartment in a building onto one address row. Only the edit-mode comparison with the saved address still joins them, so a row an older app version saved with the apartment inside `street` keeps Save disabled while the form is unchanged. The submit button is enabled once the street is non-empty, or once a picked suggestion supplied coordinates even with an empty street, and is never blocked for any other missing field. In edit mode it also stays disabled while the form still matches the saved address and no suggestion was picked, because such a post has nothing to change. The server reuses the user's own row for it only when that row was typed rather than picked ([[address-normalized-key#Finding an address during registration#A repeated unlocated submission reuses the user's own row]]). For a picked row it makes a new row and runs a full address switch: it deactivates links, records an address change and starts the cooldown. Editing any field clears the coordinates and the place types, so edited text is never posted with the location or classification of an earlier suggestion. The full set of separate fields is still shown as a fallback when:

- this platform's build has no Google Places API key
- the user taps "Edit address fields" to correct what was parsed

A failed save keeps the form as typed and leaves the submit button usable, so the user can press it again. The error line shows the server's own sentence for a JSON error envelope, such as the address-change cooldown. A request that never reaches the server, including the 15-second timeout, shows a fixed connection sentence, because the platform's abort text (for example `Aborted`) tells the user nothing. An HTML error page shows the client's friendly fallback sentence. Only an `ApiRequestError` shows its own message; any other error, such as a native or storage failure, shows the fixed sentence "Could not update address.". The saved address fills the form once per screen mount, so a background profile refresh in edit mode cannot overwrite typed text while the picked coordinates stay, and the autocomplete box is remounted once that prefill has run so its starting text shows the saved street, and picking a suggestion clears any earlier autocomplete error.

`RootNavigator` and the onboarding stack decide who gets sent here; the `isOnboarding` flag only swaps the wording and the buttons. Onboarding mode reuses the web registration page's wording, edit mode uses the same `PARITY_COPY.address.edit` and `switchConfirm.editLead` wording as the web change-address page ([[web-profile-page#Web profile page#Changing the address from the web]]), and the helper block at the bottom carries the same three outside links as the web page.

The two buttons are built from the shared `Pressable` component. Cancel logs the user out during onboarding, or goes back one screen when editing. The web change-address page has the same Cancel and returns to Profile, while its first-time registration page keeps a Log Out button like onboarding. Submit reads "Find My Representatives" during onboarding, or "Save address" when editing.

The helper block matches the divider and three outside links on the web registration page: a note about being a registered voter, then the same three links in the same order. `[platform]`: these open with `Linking.openURL` on mobile, where the web opens a new browser tab.

### Why an onboarding failure that may have saved the address reloads the account first

During onboarding, a timeout or a `confirmation_required` refusal reloads the account before any message shows.

The first post can time out on the client after 15 seconds while the server still finishes the registration. The user then edits and resubmits, and the server answers `confirmation_required` because the address now differs from the saved one. Onboarding has no confirm control, so every further resubmit would fail the same way. Reloading the account first lets `RootNavigator` move a now-registered user on, and the screen unmounts. If the reload resolves `false` after a `confirmation_required` refusal, the server may have saved the address, so the screen shows the same recovery card as [[mobile-auth-and-onboarding-flow#AddressScreen#Why a failed refresh after a saved address shows a recovery card]] instead of the server's "Please confirm to continue" sentence, because onboarding has no confirm control to act on it. After a timeout, or when the reload resolves with a payload that still shows the user unregistered, the screen shows the usual sentence and the form stays usable. Outside onboarding the user is already registered and the confirm card exists, so no reload happens.

### Why a failed refresh after a saved address shows a recovery card

During onboarding, a failed payload reload after a saved address swaps the form for a card with a "Try again" button that only reloads the payload.

After a successful post, `AddressScreen` reloads the startup payload, and `refetch` resolves `true` only when it applied a fresh payload. When it resolves `false`, the card says the address was saved and the account could not be loaded yet.

A failed reload falls back to the cached payload from before registration, which still says registration is incomplete, so `RootNavigator` keeps the onboarding stack. Showing the bare form again would invite the user to retype the address. A retyped address is an address switch, and the server answers `confirmation_required` because onboarding never sends the confirmation. The retry button posts nothing, so it cannot trigger that refusal. When the reload succeeds, `RootNavigator` swaps in the app on its own. Outside onboarding a `false` result changes nothing: the screen still goes back, because the user is already registered and the stale payload still shows their previous address. Callers that ignore the result of `refetch` are unaffected.

### Asking for a city or ZIP when the address cannot be located

When `POST /sway_registration` answers with `address_located: false`, [[mobile/src/screens/AddressScreen.tsx#AddressScreen]] stays on the screen, opens the manual fields with the submitted values preserved, and shows a card with the server's message and a continue button.

During onboarding, refreshing immediately would load `is_registration_complete: true` from the Congress fallback and cause `RootNavigator` to unmount the onboarding stack before the user could see the prompt or add a city or ZIP, so cache eviction, `refresh()`, and navigation wait until a corrected submission succeeds or the user presses `PARITY_COPY.address.notLocated.continueCta`. Outside onboarding, `is_registration_complete` is already `true` and the server switch has already committed, so caches clear and `refresh()` runs immediately before showing the card so tapping Cancel never leaves stale profile or SQLite cache state.

## Why isOnboarding only changes wording

Onboarding mode means no address has been saved yet.

The button reads "Find My Representatives", and after a successful save the profile refresh moves `RootNavigator` to the app drawer, which opens on Feed. That matches the web app, which sends a newly registered user to `/feed` ([[mobile-tab-navigation-architecture#AppDrawer#The drawer opens on Feed]]). Edit mode (an address already exists) keeps "Save address" and goes back to the profile screens. `RootNavigator` and the onboarding stack already decide the routing, so this flag only changes wording and buttons.
