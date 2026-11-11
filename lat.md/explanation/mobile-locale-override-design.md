---
lat:
  mode: explanation
---

# Mobile locale override design

The mobile app's chosen jurisdiction is tracked via a module-level variable that `apiClient` checks on every outgoing request.

When it is set, `apiClient` appends `?sway_locale_id=N`, so the server uses the locale the user picked rather than guessing.

## Why a module-level value and not React state

`apiClient` consists of plain functions rather than a React hook, so it cannot consume React context directly.

Having one writer (`BootstrapContext`) and many readers (`apiClient` calls) keeps the active jurisdiction parameter out of every individual call site.

## The lifecycle of the override value

The active jurisdiction choice transitions across three distinct lifecycle stages.

`BootstrapContext` loads the saved preference from `prefsCache` on mount. When the reader picks a jurisdiction, `BootstrapContext` writes it to `prefsCache` and updates the in-memory override. Signing out clears the override and purges the stored preference.

## Where it is persisted in prefsCache

`prefsCache` provides a key-value store in SQLite storing the user's selected jurisdiction.

The stored key `selected_locale_id` survives application restarts and accompanies API calls through `apiClient`'s locale override. Entries remain small and free of personal data; `purgeAll` clears this table when the user signs out.

## Why prefsCache stores the chosen jurisdiction in SQLite

`prefsCache` holds small settings on the device as key-value pairs in the shared SQLite database.

Persisting `selected_locale_id` allows the reader's chosen jurisdiction to persist across application restarts, mirroring the long-lived cookie behavior on the web.

## Why BootstrapContext clears the choice when the session ends outside sign-out

`BootstrapContext.fetchIt` forgets the device's jurisdiction choice when the server reports the bearer token as dead.

`useSession.signOut` clears the stored preference through `purgeAll`, but this path is triggered by the server rather than by a deliberate sign-out, so the in-memory value and the React state are cleared as well.

The same clearing occurs when `authEvents` fires `"signed_out"` or `"unauthenticated"`. Signing out or receiving notice that the token is invalid wipes stored preferences through `purgeAll`. Signing in retains whichever preference was already set on the device.
