---
mode: explanation
summary: "Why the mobile app splits auth state across two expo-secure-store keys (tokenStore, sessionStore) instead of one, and why both use WHEN_UNLOCKED_THIS_DEVICE_ONLY."
status: agent-extracted
related: [docs/explanation/mobile-bootstrap-lifecycle.md, docs/reference/mobile-api-client-contract.md]
---

<!-- vale Vale.Spelling = NO -->

# Mobile SecureStore key separation

`mobile/src/constants/api.ts` names where the server lives, plus the names
secrets are filed under. `app.config.ts` fills in `apiBaseUrl` from the
`EXPO_PUBLIC_API_URL` environment variable:

- `.env.development` → `https://localhost:3333`
- `.env.production` → `https://app.sway.vote`

`SecureStore` (the phone's encrypted keychain) holds two things and no
more: the login token (`sway_bearer_token`) and the session record
(`sway.session`). The larger startup payload is kept in the app's SQLite
database instead (see
[Mobile bootstrap lifecycle](mobile-bootstrap-lifecycle.md)).

## `tokenStore`: only the bearer token, on purpose

`tokenStore` (`mobile/src/auth/tokenStore.ts`) keeps ONLY the bearer token
string in `expo-secure-store`, the phone's encrypted storage. On purpose it
holds nothing else: just the 64-character hex token, no records, no
structures. The rest of the session lives in `sessionStore`, and the
bootstrap response lives in `expo-sqlite`.

## `sessionStore`: the whole session record, so `signOut` can revoke the device

`sessionStore` (`mobile/src/auth/sessionStore.ts`) keeps the whole session
record in `expo-secure-store`. It saves
`{ bearer_token, device_id, user_id, expires_at }` so that `signOut` can
call `DELETE /api/v1/devices/:id` with the right `device_id` BEFORE wiping
local state. Without it, the server would be left holding dead device rows
after a logout, which leaks information about the account.

## Why both stores use `WHEN_UNLOCKED_THIS_DEVICE_ONLY`

The keychain setting on both `tokenStore` and `sessionStore` is
`WHEN_UNLOCKED_THIS_DEVICE_ONLY`: readable only while the phone is
unlocked, and never synced to iCloud Keychain, so the token cannot be
copied to another device.
