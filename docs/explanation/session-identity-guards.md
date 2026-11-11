---
mode: explanation
summary: "Why ApplicationController#sign_in resets the session and stamps an identity check, and the related session-fixation and sign-in-counter decisions around it."
status: agent-extracted
related: []
---

<!-- vale Vale.Spelling = NO -->

# Session identity guards in `ApplicationController#sign_in`

## Resetting the session blocks session fixation

`#sign_in` throws away the old session and starts fresh with
`reset_session`. This blocks session fixation: an attacker planting a known
session id and waiting for the victim to sign in on it. See
[the Rails security guide's session fixation
countermeasures](https://guides.rubyonrails.org/security.html#session-fixation-countermeasures).

The inviter's id has to survive that reset — registration still needs it —
so it is captured into a local variable before `reset_session` runs and
written back to `cookies.permanent` afterward.

## Binding the session to WHO the user is, not just their id

`session[:user_id]` is a bare integer. If a dev `db:reset` reseeds a
different person onto the same id, a surviving cookie would otherwise
silently sign in as that new person. `#sign_in` also stamps
`session[:auth_identity] = user.created_at&.to_i` — `created_at` never
changes for a real user but does change on a reseed, so
`#authenticate_with_cookies` can spot the mismatch and log the session out.

`#authenticate_with_cookies` only treats this as a stale session when
`auth_identity` is PRESENT and MISMATCHES the looked-up user's
`created_at`. Older sessions with no stamp at all are backfilled with the
current user's `created_at` rather than rejected, so nobody gets logged out
merely because a deploy shipped the guard for the first time.

## Logging (not enforcing) the sign-in-counter save

`#sign_in` updates `sign_in_count`, `last_sign_in_at`, `current_sign_in_at`,
and the IP fields, then saves with a non-bang `save`. An old user row that
fails validation must still be able to sign in — the outer `rescue` already
keeps sign-in working regardless — so this save is deliberately not
`save!`; a failure is logged (`sign_in.counter_update_failed`) instead of
raised or silently discarded.

## Why `Test::SessionsController` resets the session before stamping it

`Test::SessionsController#create` (test-environment only) sets the same
session keys `ApplicationController#sign_in` sets — `session[:user_id]`
and `session[:auth_identity]` — so a test session satisfies the
stale-identity guard in `#authenticate_with_cookies`.

It calls `reset_session` first because `js: true` system specs reuse the
same browser without transactional fixtures, so a PRIOR example's cookie
jar can leave a stale `user_id`/`auth_identity` behind. Skipping the reset
leaves a stale `auth_identity` that fails the guard's mismatch check and
flakes depending on test order.

## Why `AdminSystemHelpers#sign_in_as_admin` deletes cookies before signing in, too

`spec/support/admin_system_helpers.rb#sign_in_as_admin` waits for
`root_path`'s requests to finish (`wait_until_loaded`), then explicitly
deletes every session, `refresh_token`, and `auth_identity` cookie left
behind by an EARLIER example, before starting a fresh session via the
`/test/sessions` route. This doubles up with `Test::SessionsController`'s
own `reset_session` above; belt-and-suspenders, because system specs that
drive a real browser reuse that browser between examples, and a surviving
cookie would otherwise trip the stale-identity guard on the very next
navigation — the `auth_identity` mismatches, the user is signed out, and
the admin lands back on the root page instead of the page the example
expected.
