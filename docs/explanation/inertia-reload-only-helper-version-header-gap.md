---
mode: explanation
summary: "Why some request specs build a partial-reload request by hand instead of the inertia_reload_only test helper: the helper omits X-Inertia-Version, which returns a 409 a real browser never sees."
status: agent-extracted
related: []
---

<!-- vale Vale.Spelling = NO -->

# Why some partial-reload specs build the request by hand

`inertia_reload_only`, the test helper the `inertia_rails` gem ships,
leaves out the `X-Inertia-Version` header. Without it, Inertia's
middleware answers 409 and tells the browser to load the whole page
again. The props are still computed and the test hook still records
them, which is why specs that use the helper pass without noticing — but
the status code they get back is one a real browser never sees, so "did
this come back 200" cannot be asserted through it.

Specs that need to assert on the actual response status of a partial
reload build the request by hand instead, sending the current
`X-Inertia-Version` header explicitly. That exercises the request a real
browser actually makes, rather than the always-stale one the bare helper
sends.
