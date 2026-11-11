---
lat:
  mode: explanation
---

# Error boundary hierarchy

Sway recovers from render errors with two nested layers, not one.

## App-level: the Sentry boundary

The outermost layer is a Sentry-provided error boundary wired up in `application.tsx`.

It is fixed and non-resettable: once it catches an error, only a full navigation away can clear it. Catching an error here tears down the entire app -- nav, drawer, offline banner, everything -- and replaces it with `AppErrorFallback`, a last-resort view that counts down 60 seconds before resetting local storage and session storage and reloading. `AppErrorFallback` is that view, not a boundary in its own right: it has no `componentDidCatch` of its own and does not decide when it renders -- the Sentry boundary decides that.

## Page-level: PageErrorBoundary

`PageErrorBoundary` sits inside the layouts instead of around the whole app, so a page-level render error leaves the surrounding chrome (nav, drawer, offline banner) intact.

Unlike the Sentry boundary, it resets automatically: it keys off the Inertia URL, so navigating to a healthy page clears a shown error without a manual reload, and it also exposes a "Try again" button that resets in place.

## Why both exist

Before `PageErrorBoundary` existed, the Sentry boundary was the only net: any page-level render error took out the whole app, including chrome that had nothing to do with the failure.

`PageErrorBoundary` was added to catch page render errors without that blast radius, while the Sentry boundary remains as the outer backstop for errors it does not catch (or that happen outside a laid-out page).

## Source

Source file references and component tree mappings establishing the application error boundary hierarchy.

- `app/frontend/components/error_handling/PageErrorBoundary.tsx`
- `app/frontend/components/error_handling/AppErrorFallback.tsx`
- `app/frontend/application.tsx` (Sentry boundary)

## Why PageErrorBoundary uses a resetKey prop instead of a React key

[[app/frontend/components/error_handling/PageErrorBoundary.tsx#PageErrorBoundary]] passes the Inertia URL as a `resetKey` prop rather than a React `key` so navigation clears a displayed error without remounting healthy page trees.

Keying the boundary with `key={url}` would unmount and remount every page component on every URL transition, wiping local state during same-page Inertia redirects that need to keep open dialogs intact. When a render error does occur, `componentDidCatch` delegates to [[app/frontend/components/error_handling/utils.ts#onRenderError]] so page-level and app-level boundaries share identical reporting and storage-reset behavior. [[app/frontend/components/error_handling/utils.ts#onRenderError]] clears `sessionStorage`, `localStorage`, and Cache Storage but leaves `document.cookie` untouched because assigning an empty string is not a valid `Set-Cookie` header and cannot expire existing cookies.
