---
mode: explanation
summary: "Explains who can call OrganizationFollowsController, its dual web/mobile transport, and how each action is scoped to the signed-in user's own follows."
status: agent-extracted
related: []
---

<!-- vale Vale.Spelling = NO -->

# OrganizationFollowsController access model

This controller handles following and unfollowing an organization, plus the
per-organization notification settings that ride along with a follow.

## Why the request spec once failed on purpose

`spec/requests/organization_follows_spec.rb`'s examples were written
before `OrganizationFollowsController` and its routes existed. Until
those landed, every example failed on purpose with an
`ActionController::RoutingError` inside its own body, while the file
itself still loaded cleanly — no errors at load time — pinning down the
intended behavior (POST creates a follow and is idempotent on a repeat
call, thanks to the unique key; DELETE removes it; an unauthenticated
request is always refused, never a 200; browsers get a redirect after the
write while the mobile app gets JSON) ahead of the implementation.

## Who can call it

Any signed-in user. `authenticate_sway_user!` is inherited from
`ApplicationController` and is not skipped here, so an anonymous request is
redirected on the web and gets a 401 from the mobile app. Being an
organization admin is not required.

## Transport

It serves both the website and the mobile app through `redirect_or_json`,
from the `MobileFormatNegotiation` concern.

## Write scope

Every write is confined to the signed-in user's own follows:

- `create` — built through the user association, so `user_id` is set for you.
- `destroy` — looks the row up under `current_user`, so another person's
  follow id is simply not found and the request 404s.
- `update` — guarded the same way, in `set_follow`.

## Why `#create` is idempotent and combines follow + preferences

Following twice is harmless: the database allows one row per user and
organization, so a repeat call returns the row that already exists. A new
follow copies its notification settings from the user's account-wide
defaults, via `OrganizationFollow.seed_attrs_from`.

Notification settings may also be sent with the `#create` request — the
same fields `#preferences` accepts — so the picker shown to someone who has
no follow row yet can create the follow and apply their choices in one
step, rather than requiring a second request.

## Why `#create` rescues `RecordNotUnique`

`find_or_create_by!` looks first and inserts second, with no lock in
between. Two follow requests arriving together can both find nothing and
both try to insert; the second one trips the database's uniqueness
constraint and lands in the `RecordNotUnique` rescue. That branch fetches
the row the first request created and returns the same success response,
instead of a 500. Both the ordinary path and this racing-request path
funnel through the same `follow_success_response` helper, so the two cases
answer identically.

## Why the redirect target is the referring page, not always the detail page

`back_or_organization_path` sends the browser back to whichever page it
acted from — the organizations list or one organization's detail page — so
the same React page stays mounted. Always redirecting to the detail page
would swap the page out from under a follow made on the list, unmounting
the follow control and losing the first-follow settings picker before
anyone sees it. `url_from` refuses an off-site referer; the detail page is
the fallback, which is also what the mobile app gets, since a bearer-token
request sends no referer.
