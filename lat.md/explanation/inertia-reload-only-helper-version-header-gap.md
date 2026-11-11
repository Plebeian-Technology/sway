---
lat:
  mode: explanation
---

# Why some partial-reload specs build the request by hand

`inertia_reload_only`, the test helper the `inertia_rails` gem ships, leaves out the `X-Inertia-Version` header.

Without it, Inertia's middleware answers 409 and tells the browser to load the whole page again. The props are still computed and the test hook still records them, which is why specs that use the helper pass without noticing — but the status code they get back is one a real browser never sees, so "did this come back 200" cannot be asserted through it.

Specs that need to assert on the actual response status of a partial reload build the request by hand instead, sending the current `X-Inertia-Version` header explicitly. That exercises the request a real browser actually makes, rather than the always-stale one the bare helper sends.
