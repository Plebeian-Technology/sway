---
lat:
  mode: explanation
---

# Service worker runtime caching and push handling

Architecture and runtime caching strategies for service worker static asset prefetching, lazily loaded admin assets, and Web Push notifications.

## Why parsePushPayload and resolveNotificationClickUrl are separate plain functions

Both helpers reside in separate modules outside `sw.ts` because `sw.ts` cannot be imported under Vitest or jsdom due to top-level `ServiceWorkerGlobalScope` bindings and Workbox side effects.

## Why parsePushPayload parses defensively

`parsePushPayload` guards against malformed or non-JSON payloads that would otherwise raise an unhandled exception in the push handler and abort notification display.

When parsing fails or yields a non-object payload, the push event handler displays a fallback notification using the raw text as the body rather than silently dropping the event.

## Why resolveNotificationClickUrl rejects cross-origin urls

`resolveNotificationClickUrl` validates the destination URL against the service worker origin to prevent navigation to external or untrusted destinations.

Even though push notifications use server VAPID signatures, the handler resolves target paths strictly against `self.location.origin`. It rejects cross-origin, protocol-relative, and non-HTTP URLs, defaulting to the application root.

## Why data:{url} is passed through the push notification

`sw.ts` passes through `data: { url }` on the notification options so the `notificationclick` handler can navigate to the deep-link target without an extra network round trip.

## Why includeUncontrolled:true is used when matching clients on notificationclick

Matching window clients with `includeUncontrolled: true` ensures existing Sway tabs opened prior to worker activation are reused, preventing duplicate window creation.

## Why the click handler focuses ANY same-origin window rather than an exact match

The `notificationclick` handler focuses any open same-origin Sway window and navigates it to the destination rather than requiring an exact pathname match.

Requiring an exact pathname match opened redundant tabs whenever a user already had another Sway page open. Navigating any existing same-origin window preserves single-tab navigation.

## Why dynamic navigation and page requests bypass runtime caching

Navigation and Inertia requests are excluded from service worker runtime caching because dynamic pages contain authenticated user identity, voter registrations, and user votes.

The worker registers no navigation route or page fallback. All dynamic requests go directly to the network, as detailed in [[client-caches-and-identity#What the page cache is allowed to hold]]. Retired page caches are covered in [[client-caches-and-identity#Static worker lifecycle]]. The worker responds to `DYNAMIC_PAGES_NETWORK_ONLY` messages to verify this policy during authentication preflights.

## Why runtime caching only targets lazily loaded admin assets

The only runtime route registered by `sw.ts` caches lazily loaded admin chunks under `/assets/admin/` using `CacheFirst`.

Admin chunks are excluded from build precaching to keep the initial manifest compact for normal visitors, as described in [[admin-chunks-are-not-precached#Why the precache excludes them]]. When an admin loads an admin view, the service worker caches the fingerprinted chunk. The responses `CacheControlPlugin` refuses to store are covered in [[client-caches-and-identity#What the page cache is allowed to hold]].

## Why PURGE_CACHES uses event.waitUntil

`event.waitUntil` keeps the service worker alive until all caches are deleted and the port acknowledgement is posted back to the client.

Without `event.waitUntil`, the browser could terminate the worker while cache deletions remain pending, aborting the purge and dropping the completion message.

## Where the service worker is registered

`registerSW.ts` registers the Workbox service worker via the virtual module shipped by `vite-plugin-pwa`. Registration runs once from `entrypoints/application.tsx` after `createInertiaApp` resolves.

## Why registerSW no longer has a separate pass-through hook

The React-facing `needRefresh` and `updateServiceWorker` controls are consumed directly via `useRegisterSW` inside `SWUpdateToast`.

A separate pass-through hook formerly wrapped `useRegisterSW`, but folding it directly into `SWUpdateToast` eliminated an unnecessary layer of indirection.
