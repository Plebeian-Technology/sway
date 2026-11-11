---
lat:
  mode: explanation
---

# Mobile test infrastructure notes

Why several pieces of mobile test plumbing (SQLite mock hoisting.

## billCache.test.ts and bootstrapCache.test.ts: why the mocked row shape is inline, not a named type

Jest lifts the `jest.mock("expo-sqlite", ...)` factory to the top of the file before TypeScript's types are stripped, so a named `type Row`.

Jest lifts the `jest.mock("expo-sqlite", ...)` factory to the top of the file before TypeScript's types are stripped, so a named `type Row` — even one declared right at the top of the factory — looks to Jest like a reference to something outside the factory, and it complains. The row shape is spelled out inline in the `Map` type parameter instead. Both files' mocks stand in for the one shared expo-sqlite database, held in memory, for the same hoisting reason.

## prefsCache.test.ts: why the value is kept in expo-sqlite

`prefsCache` holds small settings on the device as key/value pairs, today just `selected_locale_id`, so the chosen locale is still there after the app is fully closed and opened again.

## sentry.test.ts: mocking expo-constants and importing initSentry once

The shared `expo-constants` mock exposes `expoConfig` as a read-only getter.

The shared `expo-constants` mock exposes `expoConfig` as a read-only getter, so assigning to it silently does nothing and every example would read as "no address set." The test replaces the module with a plain object it can write to instead.

`jest-expo` runs with `__DEV__` true, so every example in this file exercises the development path; production keeps its own DSN and is untouched. `initSentry` is imported once, not re-required per example: `jest.resetModules()` would give a fresh module a fresh mock, so calls would land on an object the file never asserts on.

## App.test.tsx: why useSession and useUserProfile are mocked

`RootNavigator` picks the app drawer vs. the sign-in stack from `useSession`'s `isAuthenticated` flag. Without faking it, the app opens on Auth and the drawer never renders.

`useUserProfile` holds the app drawer back while `userLoading` is true, so the test hands back a finished profile instead, with a bare-bones address, since `RootNavigator` sends users who have no address to the address screen — the fake address lets the render move past that step.

`NavigationContainer` starts up asynchronously, since the deep-link config has to work out which screen opens first, so the test waits for the header's menu button to appear before checking the drawer items. A closed drawer is hidden from screen readers, so the items are found by their text with hidden elements included. React Navigation's drawer has no per-item accessibility label option; the item's text is the name a screen reader announces.

## jest.setup.ts: why the useFocusEffect mock has no dependency list

The shared `useFocusEffect` mock runs its callback inside a `useEffect` with no dependency list, so every render counts as regaining focus.

Running the callback inside an effect gives its cleanup a place to run on unmount. Without that, the interval `useFocusedSync` starts is never cleared and keeps Jest alive after the suite finishes.

The missing dependency list is deliberate. With `[cb]`, a rerender that hands back the same callback no longer re-runs it, and the `LegislatorDetailScreen` test that treats a rerender as regaining focus fails.

## setup.ts: why it is deliberately empty

A companion to `jest.setup.ts`, for test files that want to import setup helpers directly. It is deliberately empty for now; shared fixtures (a mock token store factory, a fake api client) can move in here later.

## accessibility.test.tsx: scope and the release-blocking policy

This file only inspects: it renders components written elsewhere and reads their accessibility settings, and never changes those files. A failure here blocks release — the app does not ship until it is fixed.

Pressing `VoteButton` reaches `expo-haptics` (the phone-vibration module), so the test stands in a fake for it, so the test never calls into native code. `UpdateBanner` needs `BootstrapContext` and the lucide `X` icon, so both are mocked as well.

The `OfflineBanner` example looks up its node by `testID` and reads `accessibilityRole` directly rather than using `getByRole`, because `@testing-library/react-native` 13 stopped translating `accessibilityRole="alert"` into a role `getByRole` can find.

## Why two examples carry an explicit 30-second timeout

`App.test.tsx` and the first example of `AddressScreen.parity.test.tsx` both fail under `dip run verify` and pass in about a second when run on their own.

Both are bound by a single React Native render — the whole navigator tree in one case, the address screen in the other — and that render is what the clock is actually measuring.

This is the opposite case from the vitest lane's warm-up fix (see [[docs/explanation/frontend-test-infrastructure-notes.md|Warming a module transform out of a test's own budget]]). There the wait was on a module transform, which could be hoisted into a `beforeAll` and taken off the clock entirely. Here there is nothing to hoist: `App` is already imported at module scope, so its transform is paid at require time, and the remaining cost is the render the example exists to exercise.

So the number is the thing to change, and jest's default of 5000ms is simply the wrong one for a full navigator render on a machine running fourteen gate lanes at once. The timeout is set per example rather than globally, so an unrelated suite that hangs still fails in five seconds, and it is set far enough above the observed worst case (about 36 seconds of suite time, of which the render is a fraction) that contention alone cannot reach it while a genuine hang — which is unbounded — still does.
