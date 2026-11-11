---
mode: explanation
summary: "Design notes for Users::PreferencesController: why #update rate-limits by IP despite skipping auth, why a theme_id-only PATCH skips the User#update call, and why each guard checks .present? rather than validity."
status: agent-extracted
related: [docs/explanation/theme-mode-and-theme-id-resolution.md]
---

<!-- vale Vale.Spelling = NO -->

# `Users::PreferencesController` design notes

## Can one user change another user's theme?

No: `preference_params` permits only the theme fields, and the controller
operates on `current_user` exclusively. There is no `id` parameter that
could point the update at a different user.

## Why `#update` is rate-limited despite skipping authentication

`#update` skips authentication, and each call triggers a signed-cookie
write plus a full Inertia redirect round trip. The global
`ApplicationController` limit is a whole-site ceiling, not a per-client
control, so a scoped per-IP `rate_limit` (30/minute) is declared on this
controller, gated by `RateLimitConfig` so tests can switch it off and
admins can tune it — matching the sibling auth-adjacent controllers
(`Users::Webauthn::*`).

## Why a theme_id-only PATCH skips the `User#update` call entirely

The signed-in path validates `theme_mode` against `User::THEME_MODES`
through the User model; the anonymous path validates inline against the
same allowlist (`ThemeHelper`). `:theme_id` is stripped before the
update — `User` has no `theme_id` column.

`#update` skips the `User#update` call entirely when the payload carries
only a `theme_id` (no `theme_mode`). `preference_params.except(:theme_id)`
would then be an empty hash, and an unguarded update would re-validate and
re-save the user with zero changed attributes — a wasted UPDATE and
callback cycle. Any payload that does carry a `theme_mode` still runs the
update, so the User model's inclusion validation (and its detailed error
envelope) still fires for invalid modes.

## Why each guard checks `.present?` rather than re-validating

Every guard in `#update` — the anonymous `theme_mode` allowlist check, the
`theme_id` allowlist check, the two cookie writes, and the final
`theme_id` cookie write — is gated by `.present?` rather than always
running full validation, for the same reason each time: an absent or
empty-string field means "nothing to do" for that field, not a 422. A
`theme_id`-only PATCH must not fail the `theme_mode` check just because
`theme_mode` is blank, and a `theme_mode`-only PATCH must not write or
validate a `theme_id` cookie it was never sent. By the time the final
`theme_id` cookie write runs, validity was already enforced by the guard
above it (which 422s any present-but-invalid `theme_id`), so only the
`.present?` check is needed there — re-running the allowlist check could
never come out false.

The cookie itself is always written when present (signed-in users get
cookie + DB; anonymous users get cookie only), so the server can read the
cookie while rendering, via `ThemeHelper#theme_preference`.

## Why the invalid-`theme_id` 422 is checked again on the bearer/JSON surface

The cookie/Inertia surface only ever answers a validation failure with
either a 422 or a re-rendered Profile page carrying errors, so a test there
can pin down only that nothing was saved, not a specific status. The
`validation_failed` envelope is checked on the bearer/JSON surface instead,
which is the surface that actually returns it.

## Testing `ThemeHelper#theme_id` resolution: seeding the signed cookie

`spec/requests/users/preferences_spec.rb`'s theme-id examples sign in with
the project's usual `_, _user = setup` pattern — the `Setup` shared context
(`spec/support/setup.rb`) creates a user with `is_registration_complete:
true` and puts `session_hash[:user_id] = user.id`, so
`authenticate_sway_user!` finds the user through `SessionDouble` with no
explicit sign-in call (this project has no Devise `sign_in` helper).

They seed the signed cookie by writing into `SessionDouble`'s backing
store, `cookies_hash` (see `let(:cookies_hash)` in
`spec/support/session_double.rb`). Because `cookies.signed` is stubbed to
return that hash, `ThemeHelper`'s `cookies.signed[:sway_theme_id]` read
gets back exactly the plain value the test put there. Do NOT call
`cookies.signed[...]=` in a test body — the request-spec `cookies` jar has
no `#signed` method, so that call raises.

## Why `theme_id` has no DB column, and why validation failures re-render a different page

`theme_mode` is written to both `users.theme_mode` (signed-in users only)
and the signed `sway_theme` cookie (all callers), so the DB copy survives
a signed-in user switching devices. `theme_id` is written only to the
signed `sway_theme_id` cookie, for all callers — there is deliberately no
`users.theme_id` column, since carrying `theme_id` across devices is out
of scope. `ThemeHelper` carries the same note; do not assume `theme_id`
writes the DB just because `theme_mode` does.

`#update` answers in two formats: cookie callers (web Inertia) get a 302
redirect to `/profile` plus a flash notice, and bearer callers (mobile
JSON) get a `{ redirect: "/profile", flash: "..." }` envelope. On
validation failure, cookie callers re-render
`Pages::USER_ORGANIZATION_MEMBERSHIPS` with error props — the closest
existing profile-shaped page, since the old web profile page is not a
single Inertia component — while bearer callers get a 422 with the
standard error envelope (`{ error: { code: "validation_failed", message:
..., details: {...} } }`).
