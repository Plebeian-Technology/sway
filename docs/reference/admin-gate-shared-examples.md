---
mode: reference
summary: "How to use the requires sway admin and requires organization admin RSpec shared examples: parameters, usage forms, and the scenarios each one checks."
status: agent-extracted
related: []
---

<!-- vale Vale.Spelling = NO -->

# Admin-gate RSpec shared examples

Two shared example groups pin admin authorization gates in request specs:
`spec/support/shared_examples/requires_sway_admin.rb` (`before_action
:verify_is_sway_admin`) and `spec/support/shared_examples/requires_organization_admin.rb`
(`before_action :verify_is_organization_admin!`).

## "requires sway admin"

```ruby
include_examples "requires sway admin",
  verb: :post,
  path: "/bills",
  params: { bill: { title: "T", kind: "local" } }
```

Parameters:

- `verb:` — HTTP method as a symbol (`:get`, `:post`, `:patch`, `:put`, `:delete`).
- `path:` — string path of the admin-gated endpoint.
- `params:` — optional hash of request params (default `{}`).

The `:sway_admin` factory trait (`spec/factories/users.rb`) sets the
`ADMIN_PHONES` constant in memory, so `verify_is_sway_admin` sees the user
as an admin without changing the phone column in the database.

The example checks three situations: a non-admin session user is blocked, a
non-admin bearer/JSON client is refused with a JSON 403 (not a redirect),
and a sway admin is permitted.

## "requires organization admin"

Path can be a plain string when it does not depend on the shared example's
fixtures:

```ruby
include_examples "requires organization admin",
  verb: :delete,
  path: "/some/static/path"
```

Or a callable, for the common case where the path needs the shared
example's `organization` / `user` / `membership` fixtures. The proc runs
through `instance_exec` inside the shared example, so it can reference
`organization`, `user`, and (where defined) `membership` directly, with no
`ctx` argument:

```ruby
include_examples "requires organization admin",
  verb: :post,
  path: -> { "/organizations/#{organization.id}/membership_invites" },
  params: { user_organization_membership_invite: { invitee_email: "x@example.com" } }
```

Parameters: same `verb:` / `path:` / `params:` shape as above.

The example checks four situations:

1. A sway admin with no membership in the organization: forbidden. Being a
   sway admin is a separate thing and does not get you past the
   organization-admin check.
2. An ordinary member (`role: :standard`, `status: :active`): forbidden.
3. A removed admin (`role: :admin`, `status: :removed`): forbidden — the
   check counts only active memberships, so a removed admin is out.
4. An organization admin (`role: :admin`, `status: :active`): allowed. The
   assertion accepts whichever success code the controller returns
   (200/201/204/302) via `.or` chaining, so callers do not need to know
   which one it is.
