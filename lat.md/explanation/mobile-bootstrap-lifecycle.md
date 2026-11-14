---
lat:
  mode: explanation
---

# Mobile bootstrap lifecycle

`BootstrapProvider` (`mobile/src/state/BootstrapContext.tsx`) loads the `/api/v1/bootstrap` payload — the current user, the active locale, feature flags, and version info the rest of the app reads through `useBootstrap()`.

## What happens, in order

Sequential initialization order managing font loading, secure token hydration, network status discovery, and root navigation.

1. On mount, the provider fetches `/api/v1/bootstrap`, stores the result in
   state, and writes it through to `bootstrapCache`, a local SQLite table.
2. If that fetch fails, the provider falls back to the cached "anonymous"
   row, so a cold launch with no network still has a locale and feature
   flags to draw the first screen with.
3. When the app returns to the foreground and the last successful fetch was
   more than 5 minutes ago (`STALE_MS`), the provider fetches again; the `AppState.addEventListener` subscription is cleaned up via its returned `.remove()` handle rather than the removed `AppState.removeEventListener` API. The provider also compares the running version against `latest_version` to compute `needsUpdate` while exposing `min_supported_version` from the server payload.

## Where bootstrap data is stored, and why

`bootstrapCache` (SQLite) is the only place this data is written.

The provider deliberately skips the keychain-backed key stores used elsewhere in the app (`tokenStore`, `sessionStore`): the bootstrap payload carries personal data and feature flags, and it can be bigger than the 2KB limit those stores enforce.

`bootstrapCache` keeps one entry per `user_id`, or `"anonymous"` when nobody is signed in; writing replaces whatever was there before.

## Why the fetch checks whether it expected to be signed in

Before reading the response, `fetchIt` notes whether it expected to be signed in.

`/bootstrap` is a public endpoint, so if the request sent a token and the answer still has `current_user: null`, that token is dead on the server: the user was deleted, or the key was revoked. The provider has to clear things out itself, because `apiClient` will not — the response was a perfectly successful 2xx.

## Why a 401 wipes the cache instead of falling back to it

A 401 means the token is no longer good on the server: the user was deleted, the key was revoked, or the token was tampered with.

Falling back to the SQLite cache here would quietly redraw personal data for an account that no longer exists, so the provider wipes the cache instead, and a relaunch cannot bring it back. `apiClient` has already cleared the token and session stores and emitted `'unauthenticated'`, so `useSession` flips over and `RootNavigator` moves to the sign-in stack on the next render. The event carries the reason `session_expired`, which `authEvents` keeps until the next sign-in or sign-out, so the `AuthScreen` that mounts after the swap can tell the user why they are back at sign-in, since the screen that hit the 401 has already unmounted and taken its own message with it.

For any other failure — no network, a server error — the provider keeps working offline by drawing the last payload known to be good. It tries the row saved for the signed-in user first, then the anonymous row.

## Why refetch reports whether it applied a payload

`refetch` resolves `true` when it applied a fresh payload, and `false` when it fell back to the cache, wiped the cache after a 401, or cleared a dead token.

The cache fallback hides a failed fetch from callers, because `bootstrap` still holds a usable payload. A caller that must know whether the server's current answer arrived reads the result. [[mobile-auth-and-onboarding-flow#AddressScreen#Why a failed refresh after a saved address shows a recovery card]] is the one that does; callers that ignore the result are unaffected.

## Why refetch listens to auth events

The provider fetches again whenever the sign-in state changes.

Without this, the payload loaded at cold start — when nobody was signed in, so `current_user` was null — would still be sitting there after signing in. `RootNavigator` would then see a signed-in user with no user record and show its could-not-load screen, so people who already have an address would be stopped at a retry prompt on every fresh launch and sign-in.

- `signed_in` → fetch again; there is a token now, so `current_user` fills in
- `signed_out` → fetch again; `current_user` goes back to null
- `unauthenticated` → fetch again; the server called the token dead, so catch up

## Why only the newest fetch may write

Only the most recently started `fetchIt` may write state or the cache; an older one that resolves later is dropped and `refetch` resolves `false` for it.

Cold start, a foreground return and `signed_in` can each start a fetch with nothing ordering them. An anonymous request begun before sign-in can resolve after the signed-in one and overwrite `current_user` with null, which would send a freshly enrolled user back to sign-in. A dropped fetch also leaves `loading` to the newer one.

## hooks/useBootstrap.ts is a pass-through

`mobile/src/hooks/useBootstrap.ts` re-exports `useBootstrap` from `BootstrapContext.tsx`.

It lets screens write `import { useBootstrap } from "../hooks/useBootstrap"` instead of reaching into the state/ folder. The real code lives in `mobile/src/state/BootstrapContext.tsx`.
