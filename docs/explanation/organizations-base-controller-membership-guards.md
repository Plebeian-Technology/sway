---
mode: explanation
summary: "Why Organizations::BaseController guards a nil current_user_membership before redirecting through it, and why a site admin with no org membership gets a direct 403 instead."
status: agent-extracted
related: []
---

<!-- vale Vale.Spelling = NO -->

# `Organizations::BaseController` membership guards

## Why `redirect_to_current_user_membership` checks for `nil` first

`verify_is_organization_admin!` already checks for a membership before
calling `redirect_to_current_user_membership`, but a future caller that
skips that gate — a site admin who belongs to no organization, say — would
otherwise crash asking a `nil` membership for its `id`. The guard makes
the method safe to call on its own.

## Why a missing membership gets a direct 403, not a redirect

When `verify_is_organization_admin!` refuses a request and there is no
membership at all (for example, a Sway admin with no organization role),
it renders `403 Forbidden` directly rather than redirecting to a
membership path that doesn't exist — there is no membership id to build
that path from.
