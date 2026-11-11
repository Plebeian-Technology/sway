---
mode: explanation
summary: "Why config.x.catch_all_enabled is true only in production, and the history of what the catch-all redirect used to send unmatched requests to."
status: agent-extracted
related: [docs/explanation/catch-all-redirect-real-request-testing.md]
---

<!-- vale Vale.Spelling = NO -->

# Why the catch-all redirect is production-only

`config/routes.rb` draws its catch-all route only when
`config.x.catch_all_enabled` is true, which `config/environments/production.rb`
sets and development/test leave unset.

## Why development and test 404 instead

Development and test let an unmatched route 404 rather than silently
redirecting to the front page. A route somebody forgot to add then fails in
front of them immediately, instead of quietly landing on a page that looks
like it worked. Production accepts the tradeoff in the other direction: a
typo'd or stale external link should land somewhere real rather than show a
visitor a 404.

That tradeoff is exactly what caused the problem described in
[Why the catch-all redirect spec makes real requests](catch-all-redirect-real-request-testing.md):
the catch-all silently swallowed the Active Storage route serving every
representative's photo, and because it redirects instead of erroring,
nothing in Sentry or any log showed it happening.

## The catch-all used to need a target address

`config.x.catch_all_enabled` used to hold an address, and `routes.rb` sent
every unmatched path there. That address named only one of the two hosts
Sway answers to, which signed out every reader who happened to be on the
other host when they hit the catch-all. The redirect now stays on whichever
host the request was actually asking for, so it needs no address at all —
just the boolean flag.

## Why the app's own machinery is excluded from the catch-all

The catch-all constraint excludes the `/rails/`, `/api/`, `/vite/`, and
`/assets/` prefixes, which must 404 instead of redirecting. A prior version
swallowed those too: `/rails/active_storage` 404s turned into silent 301s,
so broken legislator photos looked like a healthy site for a day before
anyone noticed. `/api` callers need the same treatment — a
redirect to a web page tells an external caller nothing; a 404 does.

`request.host` is already limited to `RAILS_ALLOWED_HOSTS`, so it cannot be
steered to an address this machine does not serve.

Separately, and not visible anywhere in the routes file: Cloudflare answers
`sway.vote` with a redirect to `app.sway.vote` for Firefox only, because
Firefox cannot use a passkey across related origins. That rule runs before
Rails, so Firefox never reaches this route on `sway.vote`.

The route itself is guarded to production only: one unrecognised
local request used to redirect a developer's browser to the live site with
nothing in any log. Every other environment gets a plain 404, the safer
default.

## `spec/requests/user_email_confirmation_spec.rb` records a route that does not exist

Nothing in `config/routes.rb`, no controller, and no caller anywhere in
the app mentions `user_email_confirmation`. The spec file survives
because its name reads like a feature, so an absence with nothing pinning
it invites somebody to assume the feature exists and is broken. It used
to assert a 301 to `https://sway.vote`, which was never about email
confirmation at all — it was the catch-all above answering for an address
nobody had claimed. Now that the catch-all is production-only, the
address simply is not found outside production.
