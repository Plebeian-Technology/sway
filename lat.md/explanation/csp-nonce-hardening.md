---
lat:
  mode: explanation
---

# Why the CSP nonce generator switched to SecureRandom

The Content Security Policy nonce — the one-time token that tells the browser which inline scripts are allowed to run — used to be generated with `->(request) { request.uuid }`.

That id comes from `ActionDispatch::RequestId`, which echoes back a cleaned-up `X-Request-Id` header the client sent, so the nonce was partly under the visitor's control. That was harmless while the policy only reported violations, but the wrong shape for a nonce, which must not be guessable or attacker-supplied.

The generator is now `->(_request) { SecureRandom.base64(16) }`: random on the server, new for every request, with no path back to anything the client sent.

The policy is enforced when `CSP_ENFORCE` is set, which the production deploy file does, and report-only otherwise — see [[docs/explanation/content-security-policy-directive-notes.md|content-security-policy-directive-notes.md]] for the directive-level detail.
