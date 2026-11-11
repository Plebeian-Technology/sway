---
mode: reference
summary: Contract for useSession — sign-out ordering, the two-second cache-wipe budget, and why an unauthenticated event wipes on-device caches.
status: agent-extracted
related: []
---

# useSession hook

`useSession` (`mobile/src/hooks/useSession.ts`) is whether anyone is
signed in, plus signing out of this device or of all of them.

When it starts it reads the saved session to see whether someone is signed
in. After that it listens for sign-in and sign-out announcements, so any
screen using this hook updates on its own with nothing passed down through
props.

Signing out reads the saved session before wiping anything locally. It has
to: the session holds the `device_id` needed to call `DELETE
/api/v1/devices/:id` and retire this device on the server. Wipe first and
that record is orphaned on the server after every sign-out. If the delete
call fails, local clean-up proceeds anyway — the record on the server
expires on its own when the login token does.

The local clean-up always happens, even if the server call fails. Clearing
the on-device caches is given two seconds and no more
(`CACHE_WIPE_TIMEOUT_MS`), so a damaged database file can never leave
someone stuck signed in with no way out. As on the website: a broken
database file must never leave someone stuck signed in, so any wipe
failure is written to the console and the flow moves on — the saved
session and token are already gone by the time it runs.

Closing the live server connection (`destroyConsumer`) is wrapped in
`try`/`catch` too, so the next sign-in opens a new one carrying the new
login token, and a WebSocket left half-closed cannot block sign-out.

`signOutAll` calls `POST /api/v1/sessions/revoke_all`, which signs the user
out everywhere and answers with an empty 204. If that call fails, local
clean-up happens anyway.

## The announcements it listens for

- `signed_in` → signed in
- `signed_out` → signed out
- `unauthenticated` → signed out, because the server rejected our token

Signed in means one thing only: a saved session exists on this device.

## Why `unauthenticated` also wipes on-device caches

When the server rejects our token, the on-device caches are cleared too.
Otherwise the previous session's bills, legislators and votes stay behind,
and whoever signs in next on this phone — the same person or someone
else — sees the old data. Signing out through the buttons already clears
them, but none of that runs when the server is the one ending the session.
