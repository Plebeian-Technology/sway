---
mode: explanation
summary: "Test-setup rationale, bug/feature history, and TDD-first notes extracted from mobile/__tests__/screens, hooks, and components during the first comment-extraction sweep pass over the mobile app's tests."
status: agent-extracted
related: [docs/explanation/legislators-history-per-locale-state.md, docs/explanation/sway-registration-controller-notes.md, docs/explanation/test-push-device-targeting.md]
---
<!-- vale Vale.Spelling = NO -->

# Mobile Jest test notes (first pass)

Rationale pulled out of `mobile/__tests__/{screens,hooks,components}` test
files rather than deleted outright, because it explains a decision or a
bug/feature history rather than just narrating what a test does.

## `BroadsideTabStrip.test.tsx`

These tests were written before the component itself existed, so at first
every one of them failed on purpose. They guard the parts a screen reader
depends on: every tab is marked `accessibilityRole="tab"`, the active tab
has `accessibilityState={{ selected: true }}`, and the other tabs have
`accessibilityState={{ selected: false }}`.

## `LegislatorCard.test.tsx`

These tests were written before the card was rebuilt, so at first they all
failed on purpose. They cover the card being assembled from the shared
`Card` building block, plus its score tiles and its charts toggle: the
party badge, `full_name`, and three score tile labels (Agreed / Disagreed /
No vote); each score value's `Text` sets `style.fontVariant` to include
`"tabular-nums"`, which makes every digit the same width so the columns
line up; the charts toggle opens and closes `LegislatorChartsPanel`; and
there is no charts toggle at all when `user_legislator_score` is null.

## `LegislatorChartsPanel.test.tsx`

These tests were written before the component existed, so at first they
all failed on purpose. They pin down the bar chart, which is drawn with
SVG: it draws 4 `<Rect>` bars (agreed, disagreed, abstained, no-vote), every
row carries an `accessibilityLabel` shaped `"{label} {value}"`, and when
every count is 0 no bar has a width above 0.

## `LocalePickerSheet.test.tsx`

The API sends `locale.name` as lowercase words joined by dashes, like
`"baltimore-maryland-united_states"` — the same shape the web app uses in
`sway_utils/locales.ts`. `LocalePickerSheet` runs that through
`toFormattedLocaleName`, which capitalises each part and joins them with
`", "`. The checks look for the tidied-up version, not the raw name in the
fixture.

## `MembershipCard.test.tsx` / `MembershipsListScreen.test.tsx`

Both were written to pass against the finished component/screen.
Everything is wrapped in `ThemeProvider` because the shared `Card` building
block (used by `MembershipCard`) calls `useTheme()`.

## `OrgCard.test.tsx` / `OrgDetailScreen.test.tsx`

`OrgCard.test.tsx`: written before the card was rebuilt on the shared
`Card` building block, so at first the tests failed on purpose. Following
an organization was taken out of the app at one point and later put back —
the tests that used to check "Follow" was absent now check that following
works.

`OrgDetailScreen.test.tsx`: same history — following an organization was
taken out at one point and later brought back, so the follow test checks
that the control appears instead of that it is missing.

## `StampedBadge.test.tsx`

The badge is shaped like a Bootstrap pill, and its text colour is picked so
the label stays readable against the fill. Readability is measured with
the WCAG contrast ratio, the web accessibility standard. The label `Text`
also uses `tabular-nums`, so every digit takes the same width.

The `flat()` test helper squashes a style prop down to one plain object
because it can arrive as an array or as a numeric `StyleSheet` id, and
`@testing-library/react-native` does not always flatten nested style
arrays on its own.

## `UpdateBanner.test.tsx`

The banner never blocks navigation. Whoever renders it is responsible for
putting it above the navigator.

## `VoteButton.test.tsx`

The spy (`mockImpactAsync`) is declared at the top of the file, and the
`jest.mock` factory hands back a small function that calls it. That
wrapper looks `mockImpactAsync` up when a test actually runs, by which
time the const exists. Naming it directly inside the factory would look it
up during module load, before a `const` may be read — it would silently
come back as undefined and blow up with "impactAsync is not a function".
The same shape is used in `useBills.test.ts` and its neighbours.

## `BillCard.test.tsx`

The no-inline-`shadowOffset` behavior is checked by searching the source,
so there is nothing to assert at runtime for it.

## `useBootstrap.test.ts`

The test holds on to the `AppState` listener so it can call it directly,
rather than reaching for `jest.mock("react-native", ...)` with
`requireActual`: React Native 0.83 pulls in native modules such as
`DevMenu` and `SettingsManager` that do not exist under jest, and the whole
suite crashes while loading. `jest-expo`'s preset already supplies a fake
`react-native`, so the test replaces `AppState.addEventListener` on it
instead, after the imports.

## `useSession.test.ts`

`signOut` calls `sessionStore.get()` before wiping anything, so it still
has the id it needs for `DELETE /api/v1/devices/:id`.

## `usePendingChanges.test.ts`

Written to pass against the finished hook. The last test in the file
follows one server error the whole way to the user: when the server
answers 422 with `{ error: { code: "already_finalized", message: "Change
is already finalized." } }`, `apiClient` unwraps that into an
`ApiRequestError` carrying the same code and message, the hook throws it
on, and `PendingChangesList` catches it and shows `Alert.alert("Reject
failed", err.message)`. Pinning the whole chain here means a change to
either the hook's error handling or the server's 422 body breaks the build
instead of shipping unnoticed.

## `useInviteAccept.test.ts`

These tests were written before the hook existed, so at first they all
failed on purpose.

## `AddressScreen.parity.test.tsx`

Two things here used to be checked only by hand and are now checked
automatically: that address suggestions come from the same provider, and
that the user ends up in the same place after submitting.

`AddressAutocomplete` imports `GooglePlacesSDK` as a default export. Under
jest's CommonJS loading that would land on the whole factory object, so
`__esModule: true` in the mock makes jest take `.default` instead.

## `AuthScreen.test.tsx` / `DeviceUnsupportedScreen.test.tsx`

Both wrap every render in `ThemeProvider`, because `Card` (and, for
`AuthScreen`, `Pressable`) call `useTheme()`. Neither uses
`toMatchSnapshot()`: the theme objects `Card` uses refer back to
themselves, and the snapshot formatter cannot cope with that.
`AuthScreen.test.tsx` watches `Linking` with `jest.spyOn`, the same way
`UpdateBanner.test.tsx` does it. `DeviceUnsupportedScreen.test.tsx` fakes
`expo-haptics` because `Pressable` buzzes the phone on press.

## `BillDetailScreen.test.tsx`

The "renders sections in D-13 vertical order" test walks React's internal
tree depth-first — every node's children before its siblings — collecting
each testID along the way. Where a section first shows up in that list is
where it sits on the page: swap two sections in `BillDetailScreen` and
their positions swap too, which fails the "each one comes after the last"
check. The tree is walked by hand rather than with
`UNSAFE_getAllByProps({ testID: expect.anything() })` because that
compares values literally, so a matcher like `expect.anything()` finds
nothing at all. Walking the tree is the only way to get every testID in
the order it really rendered without turning the whole tree into text,
which runs out of stack on deep `ThemeProvider` trees.

`handleVoted` is passed to `VotePanel` as `onVoted`, and `VotePanel` calls
it once a signed-in user has voted. The fake session in the "onVoted prop
passed to VotePanel is a function" test is signed out, so rather than
voting for real this test checks the wiring: `VotePanel` is handed a
function rather than `refetch` itself, and the screen mounts with the
timer in place.

## `BillsListScreen.test.tsx`

The category-chip filter test picks one chip, "Education", to distinguish
"any of the chosen categories" from "all of the chosen categories": one
fixture bill has `[Education, Police]` and must still show up, which would
fail if the filter required a bill to have all the chosen categories
instead of any of them.

## `DeepLinkRouting.test.tsx`

These tests read the `linking` settings directly. `NavigationContainer` is
deliberately not mounted, since that would drag in `react-native-screens`'
native code, which `jest-expo` cannot provide on the build server. Whether
a real link lands on the right screen is checked on a real device instead.

The `PreviousBills` route was removed. The "`BillsStackParamList` no
longer includes `PreviousBills`" test leans on a real `@ts-expect-error`
directive a few lines down: if `PreviousBills` came back to
`BillsStackParamList`, the type error would vanish, the now-unused
directive would itself become an error, and the file would stop compiling
.

## `LegislatorDetailScreen.test.tsx` / `MembershipDetailScreen.test.tsx`

Both were written before their screen existed, so at first every test
failed on purpose.

## `LegislatorsListScreen.test.tsx`

The first group of tests was written before the screen was rebuilt, so
those failed on purpose at first; the second group covers the term toggle
and the History tab. The file lives under `mobile/__tests__/screens/`
because every other mobile screen test does too.

## `NotificationPrefsScreen.test.tsx`

The hook is swapped for a mock at the top of the file. The mock returns
exactly the shape the real `useNotificationPrefs` hook returns:
`{ prefs: [...], loading, error, toggle, refresh }`. There is deliberately
no `pending` field, because the real hook does not have one.

Resolving the loading-permission-status assertion through `act` flushes
`refreshPerm`'s state update as a microtask, not a real-clock poll.
`waitFor`'s default 1s budget was the actual gate-only failure here: nothing this component does is slow, but under `dip run
verify`'s ~15 concurrent lanes the host can go long enough between
scheduling this process that a `setTimeout`-based poll misses its own
window, reproduced three separate times with the identical assertion.
`act` has no timer of its own to starve — it drains the microtask queue
the state update actually runs on.

The `OrgDefaultsCard` tests wait for the thing each
one goes on to assert, not for the card itself. The card is on screen
while the defaults are still loading, so waiting for it waits for
nothing — it passed only because the mocked request usually settled in the
same tick, and stopped passing when the verify gate gave the lane thirteen
neighbours.

## `OrgsListScreen.test.tsx`

Two assertions guard against regressions: the screen must NOT show
`testID="org-filter-bar"` (that filter bar was removed), and must NOT show
the text "Following" (the follow model was removed).

## `PasskeyManagementScreen.test.tsx`

The screen is view-only: it lists passkeys but gives you no way to remove
one, so there is no "Remove" control and no confirmation sheet. The tests
cover the four states (loading, loaded, empty, error) and check that no
removal control was left behind.
