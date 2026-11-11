---
mode: explanation
summary: "Explains why Sway has two nested error-recovery layers -- an app-level Sentry boundary and a per-page PageErrorBoundary -- and how AppErrorFallback fits as the app-level boundary's view rather than a boundary itself."
status: agent-extracted
related: []
---

# Error boundary hierarchy

Sway recovers from render errors with two nested layers, not one.

## App-level: the Sentry boundary

The outermost layer is a Sentry-provided error boundary wired up in
`application.tsx`. It is fixed and non-resettable: once it catches an error,
only a full navigation away can clear it. Catching an error here tears down
the entire app -- nav, drawer, offline banner, everything -- and replaces it
with `AppErrorFallback`, a last-resort view that counts down 60 seconds
before resetting local storage and session storage and reloading.
`AppErrorFallback` is that view, not a boundary in its own right: it has no
`componentDidCatch` of its own and does not decide when it renders -- the
Sentry boundary decides that.

## Page-level: PageErrorBoundary

`PageErrorBoundary` sits inside the layouts instead of around the whole app,
so a page-level render error leaves the surrounding chrome (nav, drawer,
offline banner) intact. Unlike the Sentry boundary, it resets automatically:
it keys off the Inertia URL, so navigating to a healthy page clears a shown
error without a manual reload, and it also exposes a "Try again" button that
resets in place.

## Why both exist

Before `PageErrorBoundary` existed, the Sentry boundary was the only net: any
page-level render error took out the whole app, including chrome that had
nothing to do with the failure. `PageErrorBoundary` was added to catch page
render errors without that blast radius, while the Sentry boundary remains
as the outer backstop for errors it does not catch (or that happen outside a
laid-out page).

## Source

- `app/frontend/components/error_handling/PageErrorBoundary.tsx`
- `app/frontend/components/error_handling/AppErrorFallback.tsx`
- `app/frontend/application.tsx` (Sentry boundary)
