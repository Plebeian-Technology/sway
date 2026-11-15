# Maestro flows for Sway mobile

Maestro is the end-to-end layer for the Sway mobile app: jest-expo covers unit
and component tests, Maestro covers whole voter journeys. Four voter flows live
here alongside the original smoke flow.

## Install

Maestro is a single binary — no Mac required for Android testing — which fits
the free-tier / host-build philosophy of this project.

```bash
curl -Ls "https://get.maestro.mobile.dev" | bash
```

## Build & install the app

Maestro drives a real Sway build, not Expo Go. Use a local EAS build — Sway
never uses a paid Expo tier:

```bash
# iOS simulator build
cd mobile && eas build --local --profile development --platform ios

# Android emulator/device build
cd mobile && eas build --local --profile development --platform android
```

Install the resulting artifact:

```bash
# iOS
xcrun simctl install booted /path/to/build.app

# Android
adb install /path/to/build.apk
```

## Store screenshots

`screenshots.yaml` is meant to capture the four App Store and Play listing
screenshots: Bill of the Month, Legislators, Previous Bills of the Month,
Organizations. It does not currently work; see the end of this section.

```bash
pnpm --dir mobile screenshots:ios
pnpm --dir mobile screenshots:android
```

They land in `assets/store/ios-screenshots/` and `assets/store/android-screenshots/`,
numbered in listing order. The booted simulator decides the image dimensions, so
boot the device class the store asks for before running. As written, the flow
clears app state first, so it starts signed out and reaches only the sign-in
screen: it does not currently capture these screens. The server must also hold
a released Bill of the Month, legislators and an organization, or the asserts
fail rather than capturing empty states.

## Flow catalog

| Flow                        | Purpose                                                               | Device requirement                                           |
| --------------------------- | --------------------------------------------------------------------- | ------------------------------------------------------------ |
| `smoke.yaml`                | Smoke — app launches, brand text visible.                             | Simulator OK.                                                |
| `deep_link_bill.yaml`       | Universal-link entry to bill detail via the `sway.vote` host.         | Does not currently work as written: it starts signed out and reaches only the sign-in screen. Needs `TEST_BILL_ID` env. |
| `open_legislator.yaml`      | Legislators list → detail.                                            | Needs a signed-in session (see below).                       |
| `voter_login_and_vote.yaml` | Passkey sign-in from a cleared app, then a vote on Bill of the Month. | **REAL DEVICE** (passkey biometric). Needs `TEST_PHONE` env. |
| `new_user_signup.yaml`      | Brand-new phone number: SMS code, passkey, typed address, then the Feed. | **REAL DEVICE** (passkey biometric). Needs `TEST_NEW_PHONE` and the address env vars; needs the SMS bypass. |
| `notifications_prefs.yaml`  | Profile → notification preference toggle.                             | Needs a signed-in session (see below).                       |

A signed-out app shows only the sign-in screen, so every flow that opens the
drawer needs a signed-in session for a fully registered account.
`voter_login_and_vote.yaml` and `new_user_signup.yaml` are the only flows that
create one: each clears app state, and the first signs in an existing account
while the second registers a new one. Run one of them first on a real device,
then run
`open_legislator.yaml` and `notifications_prefs.yaml` on that same device
without clearing state.

`voter_login_and_vote.yaml` needs:

- `TEST_PHONE`: the ten-digit US number of the account, without `+1`. The
  sign-in phone field holds ten digits only.
- An account that is fully registered, has a passkey enrolled on this device,
  and has not yet voted on the current Bill of the Month. A vote is final, so
  a second run needs a new Bill of the Month or another account.
- An operator at the device, who confirms the system passkey sheet by hand
  within 60 seconds.

`new_user_signup.yaml` needs:

- `TEST_NEW_PHONE`: a ten-digit US number, without `+1`, that has no account
  yet. The flow creates the account, so every run needs a new number; a number
  that already has an account takes the passkey sign-in path instead of
  sign-up.
- `TEST_STREET`, `TEST_CITY`, `TEST_REGION` (two letters) and `TEST_POSTAL`:
  the address to type.
- The development backend with `SKIP_PHONE_VERIFICATION` on, so any six digits
  pass the SMS step, and able to reach Nominatim for the address lookup. The
  setting reads false outside development and test.
- An operator at the device, who confirms the system passkey sheet by hand
  within 90 seconds.

`deep_link_bill.yaml` opens `https://sway.vote/bills/<id>` only. The app claims
`app.sway.vote` as well, and proving that both hostnames serve the association
files is the "Association files on both hostnames" section of
`lat.md/how-to/submit-the-mobile-app.md`, not a flow here.

## Run a single flow

Every flow reads the app id from `APP_ID`, which is the build's
`APPLE_BUNDLE_ID` (see `mobile/README.md`).

```bash
# iOS simulator must be booted first (or pass --device <id>)
maestro test -e APP_ID="$APPLE_BUNDLE_ID" mobile/.maestro/smoke.yaml

# Real device for passkey
maestro test -e APP_ID="$APPLE_BUNDLE_ID" -e TEST_PHONE=5555550123 mobile/.maestro/voter_login_and_vote.yaml

# Real device for passkey, new account (a new TEST_NEW_PHONE every run)
maestro test -e APP_ID="$APPLE_BUNDLE_ID" -e TEST_NEW_PHONE=5555550199 \
  -e TEST_STREET="100 N Holliday St" -e TEST_CITY=Baltimore -e TEST_REGION=MD -e TEST_POSTAL=21202 \
  mobile/.maestro/new_user_signup.yaml

# Run after voter_login_and_vote on the same device
maestro test -e APP_ID="$APPLE_BUNDLE_ID" mobile/.maestro/open_legislator.yaml
maestro test -e APP_ID="$APPLE_BUNDLE_ID" mobile/.maestro/notifications_prefs.yaml
```

## Run all flows

A whole-directory run (`maestro test … mobile/.maestro/`) does not currently
pass. It includes `deep_link_bill.yaml` and `screenshots.yaml`, which do not
currently work, runs `voter_login_and_vote.yaml` without `TEST_PHONE`, runs
`new_user_signup.yaml` without its variables, and sets no order that puts
either before the flows that need a session. Run the
flows one at a time, as above.

For Android, boot an emulator (`emulator -avd <name>`) or attach a device, then
run the same per-flow commands.

## Adding new flows

- One YAML per user journey; co-locate with the flow it covers.
- Prefer stable selectors (`testID`, `accessibilityLabel`) over display text a
  copy edit can change. Nothing enforces that every interactive element carries
  both: `mobile/__tests__/accessibility.test.tsx` asserts a role and a label on
  four components (VoteButton, SkeletonCard, UpdateBanner, OfflineBanner) and
  that no file under `mobile/src` disables font scaling. The flows rely on the
  `testID`s each screen already carries.
- Keep flows small (< 20 steps); split larger journeys into composable sub-flows
  under `mobile/.maestro/sub/`.
- A missing `testID` is a gap in the screen, not in the flow: file a beads
  issue against the component that should carry it. Never inline-add `testID`
  here to make a flow pass — that masks the gap.

## CI policy

**Maestro is manual-only**: CI does NOT run flows. They need a real build on a
simulator or a device, and the passkey flow needs biometric hardware.

These flows are step 2 of the real-device accessibility pass in
`lat.md/how-to/submit-the-mobile-app.md`, which is a precondition of any store
submission. Record which flows ran against which build, so the pass leaves a
dated result rather than a claim.
