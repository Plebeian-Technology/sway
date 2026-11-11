---
mode: explanation
summary: "The parseRetryAfter bug a component test could not catch, and why spec/system/rate_limit_toast_spec.rb drives a real 429 from the real Rails rate limiter through the real Inertia client."
status: agent-extracted
related: []
---

<!-- vale Vale.Spelling = NO -->

# Why spec/system/rate_limit_toast_spec.rb exists

`parseRetryAfter` was fixed as part of this spec. When Inertia's request
client rejects a "too many requests" (429) response, it hands the headers
back as a plain object with lowercased keys and no `.get` method. Reading
them the wrong way meant the throttle message never appeared in
production and the submit button never locked.

Component tests that faked the headers with `new Headers(...)` passed
anyway, because a real `Headers` object DOES have a `.get` method — the
fake did not reproduce the shape Inertia's client actually hands back.
That is exactly why this needs a real browser: a real 429 from the real
Rails limiter, arriving through the real Inertia client, is the only way
to exercise the plain-object shape the bug depended on.

## Why `ThrottleResponse.headers` accepts either shape

By default Inertia talks to the server with `XMLHttpRequest` (the app never
calls `setClient`). When the server answers 4xx, the error it throws carries
`.response.headers` as a PLAIN object with lower-cased keys and NO `.get`
method (see `parseHeaders` in `@inertiajs/core`). A real DOM `Headers` object
turns up only if you opt into the fetch-based client. `ThrottleResponse`
accepts either shape so the "too many requests" path never throws
`headers.get is not a function`.

## How the spec triggers a real 429

The 429 comes from the sign-in limit of 10 attempts per IP address every 5
minutes: ten warm-up posts are sent from inside the browser, then an
eleventh request goes out from the real submit button, so the React code
under test is what actually receives the rejection.
