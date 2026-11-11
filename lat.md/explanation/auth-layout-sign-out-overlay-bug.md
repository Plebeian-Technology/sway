---
lat:
  mode: explanation
---

# Why the sign-out handler must clear its overlay on failure

The admin nav and the regular user nav share one Sign Out handler.

When `logout()` fails, that handler has to switch the loading overlay back off. The non-admin version used to only log the error, which left the overlay stuck on until the person reloaded the page by hand. These tests call the handler on its own, because rendering the whole AuthLayout to check this is too heavy.

The overlay normally clears via `inertia:finish`/`inertia:error` listeners, but if `logout()` rejects before any Inertia visit starts, neither fires — resetting `isLoading` in the handler's own `.catch` avoids a stuck overlay.

`makeSignOutHandler` lives in its own module (`signOutHandler.ts`, not exported from `AuthLayout.tsx`) so that React Fast Refresh keeps working and this handler can be unit tested alone.
