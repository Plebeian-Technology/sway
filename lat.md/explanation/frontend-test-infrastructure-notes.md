---
lat:
  mode: explanation
---

# Frontend test infrastructure notes

Why several pieces of shared frontend test plumbing (jsdom stubs, module-registry resets, mock shapes, and test-double techniques) are built the way they are, collected from app/frontend/__tests__.

## AddressAutocomplete: mocking the hook, not the API

The component gets its address suggestions from the `useAddressAutocomplete` hook.

These tests fake the hook rather than the Google Places API behind it, so they check how the component renders, how it labels itself for screen readers (ARIA), and how it handles the keyboard — no matter where the suggestions come from.

## useScoreSubscription: the test double only implements .unsubscribe()

The hook only ever calls `.unsubscribe()` on the value ActionCable hands back, so the test double only implements that — the real Subscription class carries a much larger API (perform, send, appear, ...) this hook never touches.

Cast through `unknown` at the two call sites below rather than widening this interface to the full ActionCable surface.

## useOfflineBannerState: asserting against the hook's own source text

The hook spots the online/offline change by comparing against the previous value while it renders, not with a `useEffect` that fires after the prop changes.

React Testing Library's `act()` runs effects right away, so the one-frame-of-stale-banner bug cannot be caught by behavior here. Instead this test reads the hook's own source and insists it uses no `useEffect`.

## SwayAudio: resetting the module registry

`SwayAudio` builds its address from a bucket name supplied at build time.

The bucket is read once, when the constants module first loads, so each case here resets the module registry and imports again. Setting the variable after the import would change nothing.

Resetting the registry also clears the component's own "already reported" flag, so each case starts with Sentry never having been told.

## reportOnce: resetting two separate limits

`reportOnce` keeps two limits: one in memory for the tab, one in storage for the browser. Resetting the module registry clears the first, and a fresh stub clears the second, so each example starts from nothing.

## Why the local_storage mock needs an in-memory stand-in

An in-memory stand-in for `window.localStorage`.

WHY IT IS NEEDED. This project's jsdom window has NO localStorage at all — measured, not assumed: `typeof window.localStorage` is "undefined" even though the window has a real origin (http://localhost:3000/). Node 24 also ships its own experimental localStorage, which is switched off unless the process is started with `--localstorage-file`, so nothing fills the gap.

Code under test must therefore survive storage being absent, and any test that wants to exercise the storage path has to supply it.

## setup.ts: the ResizeObserver stub

jsdom, the fake browser these tests run in, has no `ResizeObserver`.

But Radix UI widgets built on `@radix-ui/react-use-size` — SelectContent and Popover, for instance — always call it while they lay themselves out. Put a do-nothing version in place, so tests that render those widgets do not blow up with "ResizeObserver is not defined".

## setup.ts: the matchMedia stub

jsdom has no `window.matchMedia` either.

Hooks such as `usePullToRefresh` always call it, because they assume a real browser, so any test that ends up mounting one of them dies with `TypeError: window.matchMedia is not a function`.

Put a do-nothing stand-in, shaped like a `MediaQueryList`, in place before each test, so the components render cleanly. Tests that set their own `window.matchMedia` (usePullToRefresh.test.ts, for one) keep working: their version wins for the length of that `it` block, and the next `beforeEach` puts this shared default back.

## OrganizationsNotificationsPanel: the jest-dom matcher gap

These tests use only Vitest's built-in matchers, not the extra ones from `@testing-library/jest-dom`, because that add-on does not hook itself up correctly in Vitest 4 without extra configuration.

That gap came before this file and is tracked on its own.

## OrganizationsNotificationsPanel: why the useForm stand-in must hold real state

A bare-bones stand-in for `useForm`: it holds the form data in React state and hands back the watched patch function.

The state has to be REAL state, not a captured object. The real `useForm` re-renders on `setData`, and the panel's whole point is that the switch moves on a click while the badge does not. With a mock that does not re-render, a test of that difference would pass no matter which source the badge read, so it could never fail.

Like the real `useForm`, this state is seeded once and is never re-bound to new props.

## LocalePicker: naming the expected class per theme, not just checking it is non-empty

`THEME_SELECT_CLASSES` is looked up by theme id.

If a theme is added to `THEMES` without an entry there, it quietly gets the neo control. That fallback is a fine outcome, but someone has to actually choose it, so the map below writes the choice down, one line per theme.

An earlier version of this test only checked that the class name was not empty. The `?? NEO_SELECT_CLASS` fallback makes that true for every possible input, so it could never fail, for any theme. Naming the expected styling per theme is what gives the check teeth.

## test-utils.tsx: why vi.hoisted stubs can't call a helper function

`setPageProps` and `resetInertiaStubs` work on an `InertiaStubs` object that each test must declare with `vi.hoisted`.

Vitest moves `vi.mock` calls — and the stub object they point at — above every import, so the stubs have to exist before any import runs. Calling a helper function from inside `vi.hoisted` is not safe, because that helper has not been imported yet; write the shape out inline instead.

## Warming a module transform out of a test's own budget

Four vitest files pass in seconds on an idle machine and fail under `dip run verify`, which runs fourteen host lanes at once. Every one of them was waiting on a module transform inside a fixed time budget:

- `useLogout.test.ts`, `useReachability.test.ts` and `offlineTelemetry.test.ts`
  each pull the module under test in with `await import(...)` inside the first
  example, so the first example alone pays for transforming it — against
  vitest's default 5000ms per-test timeout.
- `billLayoutRender.test.tsx` renders a `React.lazy` layout and waits for the
  Suspense fallback to clear. That wait is `waitFor`'s default budget of
  1000ms, and a cold chunk transform does not fit in it under load.

The fix is not a larger timeout. A timeout raised to cover contention no longer catches a genuine hang, and the result still depends on what else the machine happens to be doing. Instead each file resolves the same modules once in a top-level `beforeAll`, which is not on any example's clock. Vitest's transform cache outlives `vi.resetModules()` — that call clears the module *registry*, so a test that deliberately re-imports for a fresh copy still gets one, but it re-executes cached output instead of re-transforming source.

So the assertions, the timeouts and the per-test module resets are all unchanged; only the transform moved out of the timed region.
