---
lat:
  mode: explanation
---

# OrganizationFollow notification design

`OrganizationFollow` is the User↔Organization follow join model. The unique index on `[user_id, organization_id]` backs the controller's idempotent `find_or_create_by!` and prevents duplicate follows.

## Why the cadence integers are locked

`notification_cadence`'s integer mapping (`every_change.

`notification_cadence`'s integer mapping (`every_change: 0, daily: 1, weekly: 2`) must stay value-compatible with `User#org_position_cadence_default`, because `.seed_attrs_from` copies the user's stored integer straight into a new follow row without translating it. Renumbering one enum without the other would silently reassign every new follow's cadence to the wrong meaning.

## Why an unknown change type fails closed

`#muted_for?(change_type)` returns `true` (muted) for any `change_type` it does not recognize, matching the no-row branch in `Organization#notifiable_follower_set_for` — both treat an unrecognized type as not-enabled.

A future fourth notification type wired into only one of the two branches therefore fails SAFE (nobody gets an extra notification) rather than failing open into double-notifying a follower who never opted in.

## Browser coverage scope

`spec/system/organization_follows_spec.rb` covers what a user actually does, all the way through the real submit-redirect-reload cycle Inertia performs.

The tricky corners — muted follows, digest emails, sending the same notification twice, approving positions in bulk — are covered by request, service, and job specs instead. Every check in this file looks at something observable — button state, badge text, or the database — never just the URL.

## Why seeding preferences lives on the model, not the controller

`.seed_attrs_from(user)` builds the hash of per-follow preference attributes copied from the user's global default columns.

`OrganizationFollowsController#create` calls it to populate a new follow row at creation time. Keeping the seed logic on the model rather than inline in the controller makes it easy to stub in tests that don't care about the exact default values.

## Why the skipped-picker system spec sets user defaults away from the column defaults

`spec/system/organization_follows_spec.rb`'s "keeps the seeded defaults when the first-follow picker is skipped" example sets `notify_on_new_position_default.

`spec/system/organization_follows_spec.rb`'s "keeps the seeded defaults when the first-follow picker is skipped" example sets `notify_on_new_position_default: false` and `org_position_cadence_default: :daily` on the user explicitly, rather than leaving the user's defaults alone. The `organization_follows` column defaults are `true` / `every_change` — the same values a stock user's own defaults would already produce — so without this override the example's assertions would pass even if `seed_attrs_from` were never called; the column defaults alone would produce the identical row. Setting the user's defaults apart from the column's means the assertions can only pass if the follow row actually read the user's values through `seed_attrs_from`.
