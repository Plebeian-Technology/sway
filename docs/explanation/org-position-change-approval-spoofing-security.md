---
mode: explanation
summary: "Explains the cross-org approval-spoofing threat against Organizations::PositionChangesController#update, closed by the organization-scoped .joins inside set_change."
status: agent-extracted
related: ["docs/explanation/org-invite-id-enumeration-security.md", "docs/explanation/org-positions-membership-idor-security.md"]
---

# Organization position-change approval-spoofing security

`spec/security/organization_position_change_security_spec.rb` guards the
approve path of `Organizations::PositionChangesController`, in the same
spirit as `spec/security/organization_invite_security_spec.rb`.

## The attack

Someone who really is an admin of organization A calls A's own approve URL,
but passes the id of a pending change that belongs to organization B. The
`verify_is_organization_admin!` check passes, because the attacker is a
genuine admin of A. The only thing left protecting B's data is the
organization-scoped `.joins` inside `set_change`.

The trick each example exercises: an active admin of `attacker_org` calls
their own organization's approve route while passing `victim_org`'s pending
change id. The org-admin check passes, so `set_change`'s organization-scoped
join has to answer 404 for the other organization's id, leaving both the
change row and `victim_org`'s live position content untouched.

## Why this needed its own coverage

The reject path (`#destroy`) already has cross-organization tests, for both
the web and JSON callers, in
`spec/requests/organizations/position_changes_controller_spec.rb`. The
approve path (`#update`) runs the same `set_change` `before_action` but had
no such test, and approving does more damage: it does not merely stamp a
status, it writes the attacker's proposed `support`, `summary` and `active`
values over the victim organization's live position. These examples close
that gap, so a later refactor that drops the `.joins` from `set_change`
fails CI on the approve side too.

Who is allowed to do what (sway admin, non-admin, removed admin) and the 422
responses for an already-finalized change live in the request spec, through
the "requires organization admin" shared example and the finalize-guard
examples. They are deliberately not repeated here.

## Test-design convention

Each example builds its own data in local variables rather than using `let`
or a helper `def`, matching the steep-clean pattern used elsewhere in
`spec/`. The steep type checker reads an example group body as a plain
object and cannot see RSpec's memoized readers.

## Why `position_changes` has no `#index` route

`config/routes.rb` declares `resources :position_changes, only: %i[update
destroy]` — no `:index`. The controller has no `def index`, so a GET there
raised `AbstractController::ActionNotFound`. Silently adding a method there
without re-establishing the auth, format-split, and transactional re-read
contract described above is the footgun; add `:index` in the same commit as
the action, through code review, if a "rejected history" surface ever ships.

## Why an inner join is safe here

`set_change` finds the change with an inner join through
`organization_bill_positions`, filtered on `organization_id` from the URL.
Without this join, an admin of org A could guess a bare id and approve or
reject a change belonging to org B; joining and filtering means an id from
another org is simply not found, so both `#update` and `#destroy` answer
404.

The inner join is safe specifically because positions are only ever
soft-deleted (marked `active: false`) — the row never goes away, so a
change always has a position to join to. If real deletes are ever added to
positions, this join needs to switch to a left join, so an orphaned change
404s through the cross-org check rather than quietly falling out of the
join entirely.

## See also

- `app/controllers/organizations/position_changes_controller.rb` (`#update`
  and `set_change`)
- `spec/requests/organizations/position_changes_controller_spec.rb` (the
  reject-side tests)
