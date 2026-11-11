---
mode: explanation
summary: "Why a rejected Inertia request's error.response.headers is a plain lowercased-key object with no .get method, and why tests must fake that shape rather than a DOM Headers object."
status: agent-extracted
related: []
---

# Why Inertia's rejected-request headers are a plain object, not `Headers`

Inertia sends requests with XHR by default. When the server answers with an
error status, the rejected error's `.response.headers` is a PLAIN object with
lowercased keys and NO `.get` method (see `parseHeaders` in `@inertiajs/core`;
`sway_utils/rate_limit.ts` carries the same note). Building the fake error with
`new Headers({...})` would test a shape production never produces, and the
test would pass while the real code stayed broken.

This is what a real 429 looks like in production. Inertia sends requests
with XHR by default, and the error it throws carries `.response.headers`
as a PLAIN object with lowercased keys and NO `.get` method (see
`parseHeaders` in `@inertiajs/core`'s `xhrHttpClient`). A test that built the
headers with `new Headers()` would pass while production died with
`headers.get is not a function`, before the wait message ever appeared.
