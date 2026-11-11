---
lat:
  mode: explanation
---

# Why logout purges the service worker before deleting the session

`purgeServiceWorker` (`app/frontend/hooks/users/useLogout.ts`) empties every cache the service worker holds and unregisters the worker itself, before `useLogout` sends the request that deletes the session.

This matters on a shared device: without the purge, the next person to use the browser could still read cached pages that were meant only for the signed-in user.

The order is deliberate — caches are emptied first, then the worker is unregistered — following Chrome's guidance at [developers.chrome.com/docs/workbox/remove-buggy-service-workers](https://developers.chrome.com/docs/workbox/remove-buggy-service-workers). Unregistering first can leave stale caches reachable by a page that still has an old worker instance controlling it.

## Why local/session storage is cleared in onFinish, not onSuccess

`useLogout` clears `localStorage` and `sessionStorage` in `onFinish` rather than `onSuccess`, so the browser's copy of login-related data goes away even when the DELETE fails.

The trade-off is deliberate: if the DELETE fails, the server still thinks the user is signed in while their local data is gone. Logging out should behave the same way every time, and the cache purge above already runs whatever the outcome.

## Why router.flushAll() runs alongside the storage clears

Inertia's prefetch cache is a third store, separate from the service worker caches and from `localStorage`/`sessionStorage`, and nothing else empties it.

It lives as a module-level singleton inside the loaded JavaScript bundle, and its entries are keyed by the request that produced them — URL, method, data and headers — with nothing that identifies who was signed in when the response arrived.

Signing out does not reset it. The server's `clear_history: true` (`Users::Webauthn::SessionsController#destroy`) clears the encrypted history and nothing more; it never touches the prefetch cache. And because sign-out is an Inertia redirect rather than a full page load, the bundle is never re-evaluated, so the singleton survives the transition intact.

Prefetching is live on the bill rows, the legislator cards and four of the drawer's nav items, so on a shared device that would leave one reader's prefetched pages available to whoever signs in next, for as long as the entries live. `router.flushAll()` empties that cache on the way out, which is the same reasoning that puts the service worker purge above it.

This is the general form of the lesson in [[docs/explanation/per-user-locale-props-never-once.md|per-user-locale-props-never-once.md]]: any client-side cache keyed without an identity has to be emptied explicitly when the identity changes, because no cache clears itself at a sign-out that never reloads the page.
