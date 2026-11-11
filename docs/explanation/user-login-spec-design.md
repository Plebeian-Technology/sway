---
mode: explanation
summary: "Why spec/system/user_login_spec.rb splits a hand-fired passkey login from a real-UI one, the CI cookie-propagation quirk that forces that split, and how the tampered-challenge refusal is actually proven."
status: agent-extracted
related: []
---

<!-- vale Vale.Spelling = NO -->

# spec/system/user_login_spec.rb design notes

## The render check the hand-fired flow has to skip

The example that fires the passkey callback by hand (rather than through
the real login UI) deliberately does not check that the following
`visit legislators_path` renders "Representatives." That check passes
locally but fails every single time on the GitHub headless-Chrome runner:
the session created by the hand-fired callback is not recognized on the
following `visit`, so the page renders as if nobody were logged in. Other
signed-in browser specs render fine on CI, so this is a cookie-propagation
quirk of the real WebAuthn flow in the test harness, not a product bug.
That the login worked is already proven by the 303 the callback itself
returns.

## Why a second example drives the real login UI end to end

"Logs in through the real passkey UI and renders the legislators page"
types the phone number and clicks the sign-in button instead of firing the
requests by hand. The callback goes out as a real Inertia navigation,
which carries the session cookie through to the destination page — that
is why the render check the hand-fired flow had to skip can run here.

## Proving a tampered-challenge login was refused, not just redirected

Checking only for a 303 status after a tampered-signature callback proves
nothing, because the success redirect to the legislators page is also a
303 — a bug that accepted a forgery would still pass that check. What
actually tells acceptance from refusal is whether `stored_passkey.update!`
ran: `SessionsController#callback` only reaches that write — which bumps
`sign_count` and `last_used_at` — after a SUCCESSFUL verification. The
example records both values before the tampered callback and asserts they
are unchanged afterward. It cannot instead ask "is the user logged in
now?", because `register_passkey_user` already signed the user in during
setup, so that question cannot tell a correct refusal from an accepted
forgery either way.
