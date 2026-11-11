---
mode: explanation
summary: "Why the mobile app's chosen-locale value lives in a module-level variable rather than React state, and how it is set, persisted, and cleared."
status: agent-extracted
related: [docs/reference/mobile-api-client-contract.md, docs/explanation/mobile-bootstrap-lifecycle.md, docs/explanation/sway-locale-id-param-cookie-guard.md]
---

<!-- vale Vale.Spelling = NO -->

# Mobile locale override design

`localeOverride` (`mobile/src/state/localeOverride.ts`) holds a single value
at module level that `apiClient` checks on every request. When it is set,
`apiClient` adds `?sway_locale_id=N`, so the server uses the locale the user
picked rather than guessing.

## Why a module-level value and not React state

`apiClient` is plain functions, not a hook, so it cannot use context. One
writer (`BootstrapContext`) and many readers (every `apiClient` call) keeps
that parameter out of every call site.

## The life of the value

- `BootstrapContext` loads it from the prefs cache on mount.
- The user picks a locale, and `BootstrapContext` writes it to the prefs
  cache and sets it here.
- Signing out clears it; `purgeAll` removes the stored preference.

## Where it is persisted: `prefsCache`

`prefsCache` (`mobile/src/cache/prefsCache.ts`) is a tiny key/value store in
the same SQLite database as `bootstrapCache`. Today it holds only
`selected_locale_id`, which survives an app restart and rides along on
every API call through `apiClient`'s locale override, the same way the
website's long-lived cookie works. Entries are kept small and free of
personal data; `purgeAll` wipes this table when the user signs out.

## Why `BootstrapContext` clears the locale choice when the session ends outside of a sign-out

`BootstrapContext.fetchIt` forgets the device's locale choice when the
server reports the bearer token as dead (a 401-shaped `current_user: null`
on the otherwise-public `/api/v1/bootstrap` endpoint). `useSession.signOut`
clears the stored preference through `purgeAll`, but this path is triggered
by the server rather than by a sign-out, so the in-memory value and the
React state have to be cleared here too.

The same clearing happens when `authEvents` fires `"signed_out"` or
`"unauthenticated"`: signing out, or being told the token is dead, wipes the
stored preferences through `purgeAll`, so the in-memory locale and the
React state are cleared before fetching again. Signing in keeps whatever
choice was there: a different account on the same device still sees that
device's locale.
