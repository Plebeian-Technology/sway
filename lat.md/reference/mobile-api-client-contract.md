---
lat:
  mode: reference
---

# Mobile apiClient contract

`apiClient` (`mobile/src/api/client.ts`) is a small JSON HTTP helper around `fetch()`. It signs every request with a bearer token.

## Methods

Supported HTTP request signatures, parameter structures, and return types provided by the mobile API client.

```
apiClient.get<T>(path, opts?)        : Promise<T>
apiClient.post<T>(path, body, opts?) : Promise<T>
apiClient.patch<T>(path, body, opts?): Promise<T>
apiClient.delete(path, opts?)        : Promise<void>
```

- Every method takes an optional `signal: AbortSignal`, so a screen's hook can cancel a request that is still running when the screen goes away. That stops the React warning about setting state on a screen that is gone, which happens when someone switches between tabs on a slow network. An `AbortError` raised by the caller's own signal is swallowed rather than surfaced as a failure.

## Auth

Each request reads the bearer token from `tokenStore` and sends `Authorization: Bearer <token>`.

## Errors

The server may send either error shape; `apiClient` accepts both — the JSON:API-style `{ errors: [...] }` array, and the older `{ error: { code, message, details? } }` object.

- `401` → clears both `tokenStore` and `sessionStore`, then throws `UnauthorizedError`
- `429` → throws `RateLimitedError`
- any other non-2xx → throws `ApiRequestError`
- `fetch` itself failing (DNS, TCP) → throws `NetworkError`

## Security

`apiClient` never logs the `Authorization` header. Stripping it from Sentry breadcrumbs is handled elsewhere.

## Why the server error shape has a code field

The `{ error: { code, message, details?

- } }` envelope (`app/controllers/concerns/json_error_renderable.rb`) is one shape for every JSON error the Rails app returns, so `apiClient` and its callers can branch on `error.code` rather than parsing `message` text.

## Why the API base URL is logged once at startup

Print the API base URL to the Metro log the first time this file loads, so it is obvious which backend the running app talks to.

- `EXPO_PUBLIC_API_URL` is fixed when the app is built, so logging it once at startup catches a mismatch (localhost vs. the dev tunnel host) between the app and the domain passkeys are registered against — the WebAuthn relying party id — without logging every request.

## Why locale overrides ride on every request

Once the user has switched to another locale (a city, state, or federal jurisdiction), `apiClient` adds `sway_locale_id` to every request so the server's `find_current_sway_locale` honours the choice.

- This stands in for the long-lived cookie the website sets. If the URL already carries its own `sway_locale_id`, `apiClient` leaves it alone — callers such as locale-switching deep links win. See [[docs/explanation/mobile-locale-override-design.md|Mobile locale override design]] for how the value is stored and cleared.

## Why both server error envelope shapes are converted the same way

The array form (`{ errors: [...] }`) is what the server is meant to send; some older endpoints still send the older `{ error: {...} }` shape.

- Either way `apiClient` converts it to the same internal error object, so the `code` checks in `passkeyAuth` and the SMS fallback keep matching (`"no_passkey_enrolled"` and the rest). `detail` (and `source` where useful) passes through as `details`, so screens can keep showing the specifics.

## Why the error classes are separate subclasses

`ApiRequestError`, `UnauthorizedError`, `RateLimitedError`, and `NetworkError` all carry the same fields the server sends.

- Separate subclasses let callers react to auth, rate-limit, and network problems without inspecting status codes themselves:

```
try { ... } catch (e) {
  if (e instanceof UnauthorizedError) navigate to login
  if (e instanceof RateLimitedError) toast "slow down"
  if (e instanceof NetworkError) show offline banner
}
```

## Why a 401 also closes the WebSocket, and why that import is inline

On a 401, `apiClient` also closes the ActionCable WebSocket.

- Otherwise it stays connected using the token the server just rejected, until the user signs out by hand. The `channels/consumer` import sits inside the 401 branch rather than at the top of the file so these two modules can never end up importing each other in a loop — `channels/consumer` does not import `api/client` today, and this keeps it safe if that changes. `authEvents.emit("unauthenticated")` fires AFTER the stores are cleared, so listeners (`useSession`, which flips `RootNavigator` to the sign-in screens) see a consistent state.

## Why authEvents imports nothing

`authEvents` (`mobile/src/auth/authEvents.ts`) is a tiny announcer that tells interested code when the sign-in state changes:

- `"signed_in"` — sent by `passkeyAuth`/`smsAuth` after a successful login
- `"signed_out"` — sent by `useSession.signOut` / `signOutAll`
- `"unauthenticated"` — sent by `apiClient` when the server answers 401
  (the session was revoked, the token expired, and so on)

- `useSession` listens, flips `isAuthenticated`, and `RootNavigator` re-renders.

- This file deliberately imports nothing, so `apiClient` (low level) and `useSession` (higher level) can both import it without the two ending up in an import loop.
