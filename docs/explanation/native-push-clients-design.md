---
mode: explanation
summary: "Explains why NativePushDispatcher wraps FcmClient and ApnsClient's own DeviceNotRegisteredError classes into one, why FcmClient caches its OAuth token in process memory instead of Rails.cache, and why ApnsClient keeps one connection pool per thread."
status: agent-extracted
related: [device-push-token-management.md]
---
<!-- vale Vale.Spelling = NO -->

# Why the native push clients are built the way they are

`NativePushDispatcher` picks the delivery client by `UserDevice.platform`:
`FcmClient` for Android, `ApnsClient` for iOS.

Each client raises its own `DeviceNotRegistered` error; `NativePushDispatcher`
wraps both into a single `DeviceNotRegisteredError` so `SendNativePushJob`
can rescue one class and revoke the dead device — see
[device-push-token-management.md](device-push-token-management.md) for
what happens on that revocation.

## Why FcmClient caches its OAuth token in process memory, not Rails.cache

`TOKEN_MUTEX` guards an in-process OAuth token cache. Google hands out
tokens per client freely, so each Solid Queue worker process caching its
own bearer token is fine — and in-memory caching keeps the live credential
off disk (`Rails.cache` is a disk-backed store on the Pi).

## Why ApnsClient keeps one connection pool per thread

Each thread builds its own pool of connections the first time it needs
one and keeps it in `Thread.current`, so every Solid Queue worker thread
has a pool to itself. apnotic v1.x `ConnectionPool` is not safe to share
between threads.

## Why FcmClient never logs the push token

Privacy guard: this client never logs the push_token; only the truncated
error reason is surfaced (Rails filter_parameters scrubs request-side leaks).
