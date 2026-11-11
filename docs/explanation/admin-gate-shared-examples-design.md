---
mode: explanation
summary: "Why the admin-gate shared examples check status-or-flash/exact-refusal-shape rather than a fixed redirect URL, the registration-redirect trap their non-admin contexts guard against, and the bearer-client coverage gap they closed."
status: agent-extracted
related: [admin-gate-shared-examples]
---

# Why "requires organization admin" checks status-or-flash, not a fixed URL

`Organization#verify_is_organization_admin!` redirects to the CURRENT
user's own membership page when it blocks, and that page's id is
different for every user — so, unlike `requires_sway_admin.rb`, there is
no single fixed URL the shared example can pin against. What every
blocked response DOES share, no matter which branch of
`verify_is_organization_admin!` answers it (JSON 403, plain-text 403 for a
nil membership, or a redirect for a present-but-non-admin membership), is
either a 403 status or `flash[:alert] == "Forbidden"` — the exact string
the gate itself sets. `#gate_blocked_response?` checks for that
disjunction. A controller action's own failure branches use other flash
text (`"Invalid role."`, `"Could not approve change."`, ...), so this
cannot collide with a permitted request that merely failed for its own
reasons.

## Why "requires sway admin" checks for exactly two refusal shapes

`verify_is_sway_admin` refuses in exactly two ways: a 403 for mobile and
bearer-token clients, or a redirect to `root_path` for browser pages.
`#gate_blocked_response?` in `requires_sway_admin.rb` checks for exactly
those two, and no looser a check would do: recognising only one of them,
or accepting "any redirect away from `/admin`", proves nothing — a
controller redirecting after a successful POST, and
`authenticate_sway_user!` bouncing a half-registered user to
`/sway_registration`, both LOOK like a blocked gate under a looser check,
so the shared example would pass even against a controller with no admin
guard at all.

`#gate_outcome_description` builds the failure message without assuming
`response` is present, because the controller action can raise before any
response is committed.

## Why the non-admin contexts force `is_registration_complete: true`

A `before_create` callback always resets `is_registration_complete` to
`false`, so a plain `create(:user)` gets redirected to
`/sway_registration` by `authenticate_sway_user!` before
`verify_is_organization_admin!` ever runs — the same trap
`requires_sway_admin.rb` documents and works around. Without forcing
`is_registration_complete` back to `true` with `update_column` after
creation, the "forbidden" assertion in each non-admin context was passing
because of the REGISTRATION redirect, not because the org-admin gate
blocked anything — a passing test that proved nothing about the gate it
was meant to check.

`requires_sway_admin.rb`'s own `"when user is not a sway admin"` context
guards against the identical trap the same way, for the same reason:
`User`'s `before_create` always resets `is_registration_complete` to
`false`, so setting it in the factory never sticks, and a user who has not
finished registering gets redirected to `/sway_registration` by
`authenticate_sway_user!`, which runs BEFORE `verify_is_sway_admin` and
would leave the admin check untested.

## Why the bearer-client context asserts the exact 403 shape, and clears the session first

`verify_is_sway_admin` refuses in TWO ways, and for a while the shared
example only ever reached one of them. `mobile_api_request?` is
`bearer_authorization_header? || request.format.json?`
(`MobileFormatNegotiation`), and the cookie-session context sends neither
— so the `response.status == 403` branch of `#gate_blocked_response?`
could never run from there. That left the refusal for JSON and bearer
clients — half of a SECURITY control — covered on exactly one of the
twelve admin-gated controllers (`bills#update`, in
`dual_format_negotiation_spec.rb`). Deleting that branch, or a future
controller answering bearer clients with something other than a 403,
would have gone unnoticed everywhere else.

The `"when a bearer client is not a sway admin"` context asserts the exact
shape (`response.status == 403`, JSON media type, `error.code ==
"forbidden"`, no `Location` header) rather than reusing
`#gate_blocked_response?`: the whole point is that a bearer client must
NOT get the redirect, so accepting "403 or redirect" here would recreate
the same coverage hole.

The BEARER token must be the only identity on the request for this to
prove anything. Several of the files that include this shared example
sign an admin in at the file level (`before { sign_in admin }` /
`before { session_hash[:user_id] = admin.id }`), and `sign_in` is nothing
more than `session_hash[:user_id] = user.id` — a cookie session, which
beats the `Authorization` header. Without explicitly deleting
`session_hash[:user_id]` first, `current_user` came back as that
file-level admin and the check correctly PASSED — a flaw in the test
setup, not in `verify_is_sway_admin`. This `before` hook is declared
deeper in the example group than the file-level one, so RSpec runs it
second, after the file-level `before` has already set the session.

## Why the happy-path example only re-raises RSpec's own failures

`"when user is a sway admin"`'s example wraps the request in a `begin`
that treats any raised error as "the gate did not block" rather than a
test failure — the check itself passed; a later error (missing fixture
data, say) is a problem with the action, not with the admin gate under
test. It re-raises `RSpec::Expectations::ExpectationNotMetError` and
`RSpec::Mocks::MockExpectationError` specifically rather than swallowing
everything, because those two mean the SPEC ITSELF is broken — swallowing
them would hide a broken spec setup behind a green result instead of
surfacing it.
