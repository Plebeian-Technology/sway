---
lat:
  mode: explanation
---

# Mobile app chrome and sheets

Design rationale for mobile app-chrome and modal-sheet components: AuthPromptSheet, DestructiveSheet, LocalePickerSheet, and UpdateBanner.

## AuthPromptSheet

The sheet that asks a signed-out user to sign in.

It appears when someone who is not signed in taps Vote or Follow; browsing without an account is allowed, so this is where we ask. It is a React Native Modal styled as a bottom sheet: presentationStyle="pageSheet" on iOS, a slide-up animation on Android.

Default wording, for voting:

- Heading: "Sign in to vote" — 28pt semibold display type, because this is the moment
  people are most likely to sign up.
- Body: "Track your legislators and vote on bills in your district."

Wording for following:

- Heading: "Sign in to follow"
- Body: "Follow civic organizations and get notified when they take a position on legislation."

Pass the `heading` and `body` props to swap the defaults for these.

- Main button: "Sign in" — accent background, white text, soft shadow (shadowBold).
- Secondary link: "Continue browsing" — muted colour, no underline.

Accessibility: every tappable element carries an accessibilityRole and an accessibilityLabel.

## DestructiveSheet

The "are you sure?" sheet that slides up from the bottom before anything irreversible happens. It covers three actions:

- Account deletion
- Signing out all devices
- Passkey removal

How it is built:

1. A bottom sheet holding the confirmation wording, which the caller supplies.
2. A red, full-width button labelled with the action's own name.
3. A "Cancel" link below it in the muted colour, with no icon.
4. No second step where the user types the word to confirm — this sheet is the
   only gate.

Accessibility:

- The dimmed backdrop is a button, so a VoiceOver user can tap anywhere to close.
- The red button is a button whose label is exactly the action name.
- Cancel is a link.

Look: red background from the destructive colour. Open Sans SemiBold for the heading, Open Sans Regular for the body.

## LocalePickerSheet

Bottom sheet presentation enabling mobile users to switch between supported municipal, state, and federal jurisdictions.

In [[mobile/src/components/SwayLocalePickerSheet.tsx#SwayLocalePickerSheet]], the trigger row is a pale-blue control with a primary border and a primary chevron, mirroring the web app's bordered control and opens the native `ActionSheetIOS` picker on iOS or a custom `Modal` containing a `FlatList` of [[mobile/src/components/ui/ListRow.tsx#ListRow]] items on Android.

### withHoriztonalMargin prop

For screens that already pad the sides, so the trigger can stretch edge to edge.

## Sheet backdrop: tap-through guard

`AuthPromptSheet`, `DestructiveSheet`, and `OrgPreferenceSheet` each wrap their content in an inner `Pressable`/`RNPressable` with an empty `onPress={() => {}}`.

The sheet itself swallows taps so that tapping inside it does not fall through to the backdrop's `onPress` and close the sheet.

## UpdateBanner

A strip above the app's screens telling the user a newer version exists.

It shows only when the startup payload from the server says `needsUpdate === true`, meaning the installed app is older than the newest release Rails knows about.

It nudges; it never blocks:

- Navigation keeps working. People can ignore the banner and carry on.
- The dismiss button hides the banner until the app is next launched.
  Nothing is saved to disk, so it comes back on the next launch if the app
  is still out of date.
- The Update link opens https://sway.vote/download, one URL that forwards
  to the App Store or the Play Store depending on the device.

Screen-reader and touch details:

- "Update" is a pressable announced as a link.
- Dismiss is a pressable announced as a button, read out as
  "Dismiss update banner". Both are at least 44pt tall so they are easy to
  hit with a thumb.
