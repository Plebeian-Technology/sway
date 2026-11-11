---
lat:
  mode: explanation
---

# Service worker scope and caching headers

`ServiceWorkerAllowedMiddleware` (`app/middleware/service_worker_allowed_middleware.rb`) adds two headers to the response serving the service worker script (`/vite/sw.js` and its `-dev`/`-test` variants).

## Service-Worker-Allowed: /

Without this header, a worker served from `/vite/sw.js` can only control `/vite/*`. That silently breaks the navigation cache and push subscriptions on every other page.

## Cache-Control: no-cache

Caches along the way — Cloudflare, the browser — must not hold a stale worker file, because only a fresh fetch lets the browser detect a changed script and update it.

See [web.dev: Learn PWA — Service workers](https://web.dev/learn/pwa/service-workers) for the underlying update lifecycle.
