---
lat:
  mode: explanation
---

# Why fingerprinted assets are cached for a year

Production sets `config.public_file_server.headers` so everything Rails serves out of `public/` carries `Cache-Control: public, max-age=31536000, immutable`.

Before this, production set no header at all, unlike development and test which both set one. Static assets are served by Rails' own static middleware inside Puma — there is no production Caddy, no propshaft and no Thruster — so with the origin silent, Cloudflare fell back to its default browser TTL, observed live as four hours on a fingerprinted chunk. Every expiry sent the request back to a single container on a single Pi.

## Why a year is safe rather than reckless

The filenames are content hashes, so a given URL's bytes never change; a new build produces new names.

The risk a long TTL normally carries is the opposite one — a browser holding an old `index.html` that asks for chunks the new deploy deleted. That cannot happen here, because `config/initializers/inertia.rb` sets `config.version = RailsVite.digest`. Inertia sends that fingerprint with every response and forces a full page load when it changes, so a client is moved onto the new build rather than left requesting pieces of the old one. The two settings depend on each other: shortening or removing the Inertia version would make this header unsafe.

`immutable` is what stops a revalidation request on reload, which `max-age` alone does not prevent.

## Why ServiceWorkerAllowedMiddleware sits before ActionDispatch::Static

[[app/middleware/service_worker_allowed_middleware.rb|ServiceWorkerAllowedMiddleware]] is inserted before `ActionDispatch::Static` in [[config/application.rb]] so requests for `/sw.js` receive `Service-Worker-Allowed: /` even when Rails serves the static bundle directly.
