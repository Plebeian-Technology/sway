---
lat:
  mode: explanation
---

# Service worker runtime caching and push handling

Architecture and offline caching strategies for service worker asset prefetching, network fallback, and Web Push notifications.

## Why parsePushPayload and resolveNotificationClickUrl are separate plain functions

Both are pulled out of `sw.ts` because `sw.ts` itself cannot be imported under vitest/jsdom — it has top-level `ServiceWorkerGlobalScope` code and Workbox side effects.

## Why parsePushPayload parses defensively

The WebPush push handler used to do `JSON.parse(event.data.text())` with no guard, so a malformed or non-JSON push payload threw inside the event handler — a throw a test cannot catch, and one that aborts showing the notification.

`parsePushPayload` parses defensively and returns null on any failure or a non-object result, so the handler can bail out cleanly.

`sw.ts`'s push handler still shows a notification on a malformed payload (using the raw text as the body) instead of silently dropping the push event. `parsePushPayload` is the single parse guard.

## Why resolveNotificationClickUrl rejects cross-origin urls

The push payload's `data.url` is server-controlled (VAPID-signed).

The push payload's `data.url` is server-controlled (VAPID-signed), but the handler still resolves it against its own origin and rejects anything cross-origin, so a misconfigured or future user-influenced payload can never open an arbitrary site — including protocol-relative (`"//evil.com"`) and absolute-URL payloads.

## Why data:{url} is passed through the push notification

`sw.ts`'s push handler passes through `data:{url:}` so the `notificationclick` handler can open the deep-link without a second network round trip.

## Why includeUncontrolled:true is used when matching clients on notificationclick

`includeUncontrolled:true` so a Sway tab that has not reloaded since this service worker activated is still returned (there is no `clients.claim()` here).

`includeUncontrolled:true` so a Sway tab that has not reloaded since this service worker activated is still returned (there is no `clients.claim()` here) — otherwise a duplicate tab would open even though one is already open, breaking the promise to focus an existing window instead.

## Why the click handler focuses ANY same-origin window rather than an exact match

Focus ANY same-origin Sway window and navigate it to the target, rather than requiring an exact-pathname match, which never holds for a window on a different page — an exact match always opened a second tab.

## Why config.version is set to RailsVite.digest for navigation requests

`config.version` is set to `RailsVite.digest`; without that, a stale cached HTML shell triggers an Inertia 409 error. `NetworkFirst` keeps the page shell fresh while the browser is online.

## Why FreshnessIndicator needs its own postMessage hooks

`RevalidatingPlugin` implements Workbox's `requestWillFetch`/`fetchDidSucceed`/`fetchDidFail` hooks so `FreshnessIndicator` can show a spinner while background revalidation (stale-while-revalidate) is in progress.

Without this, `useFreshness.isRevalidating` would never change.

## Why the catch-all cache is a flat 80-entry limit

A flat 80-entry LRU cache, used as a rough stand-in for a real quota (about 20 bills × 3 locales, plus headroom for vote history, profile and legislator pages). Scoping the cache per locale was deferred to a later change.

## Why PURGE_CACHES uses event.waitUntil

Keep the worker alive until every cache is deleted AND the port ack is posted.

Keep the worker alive until every cache is deleted AND the port ack is posted — without `event.waitUntil` the service worker can be killed mid-purge (the awaits resolve on a worker that may already be terminated, dropping the deletions and the ack).

## Why registerPWA checks the CACHE_HIT message type exactly

`registerPWA` routes the service worker's `CACHE_HIT` postMessages into `trackOfflineEvent`, and checks `event.data.type` for an exact match before acting, as a guard against acting on an unexpected message shape.

## What useFreshness reads and returns

`useFreshness` (`app/frontend/hooks/useFreshness.ts`) reads the cached response timestamp for the given pathname from the `inertia-pages` Cache API entry, so it can be shown as a "Last synced HH:MM" date.

It also listens for the REVALIDATING/REVALIDATED postMessages described above from the service worker to show an inline spinner while it re-fetches data in the background.

It returns `{ lastSynced: null, isRevalidating: false }` when the Cache API isn't available (server-side rendering, or no service worker) — `FreshnessIndicator` doesn't render anything when `lastSynced` is null.

## Where the service worker is registered

`registerSW.ts` registers the Workbox service worker via the virtual module shipped by `vite-plugin-pwa`. It's called once from `entrypoints/application.tsx`, after `createInertiaApp` resolves.

## Why registerSW no longer has a separate pass-through hook

The React-facing `needRefresh`/`updateServiceWorker` surface is consumed via `useRegisterSW` (`virtual:pwa-register/react`) directly inside `SWUpdateToast`.

The React-facing `needRefresh`/`updateServiceWorker` surface is consumed via `useRegisterSW` (`virtual:pwa-register/react`) directly inside `SWUpdateToast` — a separate pass-through hook used to sit between them but was folded into that component.
