---
mode: explanation
summary: "Why the shared \"requires sway admin\" example can pass on a controller with no admin guard at all, and how affected specs write a test that actually discriminates"
status: agent-extracted
related: [docs/explanation/bill-of-the-week-schedule-admin-guard-order.md]
---

# Why the shared admin example needs a discriminating companion on some controllers

`spec/support/shared_examples/requires_sway_admin.rb` accepts ANY redirect
away from the action under test as proof the guard fired. That is enough
on most controllers, but it silently passes on two shapes of controller
even with `before_action :verify_is_sway_admin` deleted entirely.

## Shape 1: the shared example's own non-admin never reaches the guard

The shared example's non-admin is built with
`create(:user, is_registration_complete: true)`. `User`'s `before_create`
callback puts that flag back to `false` on every insert, so
`authenticate_sway_user!` redirects the request to `/sway_registration`
before `verify_is_sway_admin` ever runs — the shared example never
actually asked whether the admin check exists.

`BillOfTheWeekScheduleController admin gate` in
`spec/requests/admin_bill_of_the_week_schedule_spec.rb` adds a companion
example using a non-admin whose registration really is complete:
`update_column` writes past the `before_create` reset, the same trick the
`:sway_admin` factory trait uses, so the request reaches
`verify_is_sway_admin` and is stopped there. Proof that it discriminates:
delete `before_action :verify_is_sway_admin` and the redirect goes to the
bill creator instead, `set_bill` changes
`scheduled_release_date_utc`, and both checks in the companion example
fail.

## Shape 2: the controller's own success path also redirects away from admin

On `BillDraftOrgPositionsController`, a *successful* reject also
redirects — to `summary_bill_creator_path`, which is not an admin path.
So the shared example passes whether the guard is there or not: any
redirect, including the one a genuine reject produces, satisfies it.

The companion example in
`spec/requests/bill_draft_org_positions_idempotency_spec.rb` (`"when a
non-admin attempts to reject a draft"`) checks what actually happened
instead: a non-admin's reject is refused, they land on the root path, and
`draft_org_positions` is left untouched. Proof that it discriminates:
comment out `before_action :verify_is_sway_admin` and both checks fail —
the redirect goes to `summary_bill_creator_path` and the draft is gone.

That example's non-admin is built the same way as Shape 1's: a fresh
`create(:user)` with `is_registration_complete` pushed to `true` by
`update_column` after creation, written inline rather than as a nested
`let` so Steep can see the local variable. `ADMIN_PHONES` is already
fixed to the admin defined earlier in the file, so a user with a fresh
phone number is genuinely not an admin.

## A second technique for the same problem: attaching a `UserLegislator`

`spec/requests/dual_format_negotiation_spec.rb`'s "admin-gated
bills#update with bearer token" group needs the same thing Shape 1 needs
— a non-admin whose registration really is complete — but reaches it a
different way: rather than `update_column`, it attaches a
`UserLegislator` to a freshly created user. `authenticate_sway_user!`
calls `complete!` on the first request when a `UserLegislator` is
present, so the attachment lets the bearer request reach
`verify_is_sway_admin` instead of being redirected to
`/sway_registration`. `User.before_create` still sets
`is_registration_complete` back to `false` on every insert, the same
reset both techniques exist to route around.

This spec also pins the mobile-vs-web split in
`verify_is_sway_admin` itself: a bearer client that fails the
admin check gets a JSON 403, while a browser still gets redirected to the
root path — see
[the API admin-gate doc](api-request-admin-gate-double-render-guard.md)
for the mechanism behind that split.
