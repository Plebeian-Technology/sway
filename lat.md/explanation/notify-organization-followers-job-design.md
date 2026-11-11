---
lat:
  mode: explanation
---

# Why NotifyOrganizationFollowersJob is shaped the way it is

`NotifyOrganizationFollowersJob` is a job wrapper for `NotifyOrganizationFollowersService`.

It keeps the `after_commit` callback fast by pushing the follower fan-out into a background job. The service is rebuilt from plain serializable values (ids + `change_type` strings) because ActiveRecord objects cannot be reliably serialized across job boundaries.

`OrganizationBillPosition#notify_followers_on_change` (see [[docs/explanation/organization-bill-position-notification-callbacks.md|the callbacks doc]]) is the ONE trigger for this whole pipeline. That single callback also covers the bulk admin path: `OrganizationBillPositionsController#create` upserts one row at a time (`find_or_initialize` + `save!`), so the SAME `after_commit` fires once per genuinely-changed position, with the right change-type label and a stable delivery token. The controller used to call `NotifyOrganizationFollowersService` explicitly after the bulk insert; that explicit call is GONE. It must not be re-added — a committed bulk change would notify followers twice, once from the explicit call and once from the callback.

## Fan-out cadence, the master gate, and batched lookups

Fan-out follows the follower's chosen cadence: `every_change` sends now on ALL enabled channels (web push, native push, SMS); `daily` / `weekly` hand off to `DigestOrgNotificationAggregator`.

Master gate: the user's `org_position_taken` `NotificationPreference` must be enabled. Push goes only to the follower's own subscriptions, never to all subscribers. Lookups are batched — no per-follower queries.

## Why delivery_token defaults to nil and is passed through verbatim

`delivery_token` is the per-event token that makes a repeated delivery detectable, captured at enqueue time (it is the triggering change's `updated_at`).

It defaults to nil so any job enqueued before this argument existed still runs (the service falls back to the position's current `updated_at`). A Solid Queue re-dispatch carries the SAME token verbatim, so the sent-marker collides and the replay is suppressed.

## The sent-marker table: OrgNotificationDelivery

`OrgNotificationDelivery` is the permanent record that one notification was already sent, so the same event never notifies the same person twice.

`#dispatch_immediate` inserts one row per `(organization_bill_position_id, user_id, change_type, delivery_token)` before sending. Because `delivery_token` is the triggering change's `updated_at` (iso8601), the row's unique index distinguishes a genuinely-later same-type change (a new token, so the insert succeeds and the notification delivers) from a retried or replayed `NotifyOrganizationFollowersJob` (the same token, so the insert raises `RecordNotUnique` and the send is skipped). Web push, native push, and billable SMS are never re-sent for the SAME event this way, but a real later change on the same position is never suppressed by an earlier one.

`organization_bill_position_id` is a plain integer column, not a database foreign key: organization bill positions are soft-deleted (`active: false`), never destroyed, so a marker referencing one never dangles. `user_id` IS a real relationship — `User has_many :org_notification_deliveries, dependent: :destroy` — because user rows ARE destroyed, and a lingering marker for a deleted user would serve no purpose.

## Why dispatch_immediate deletes the marker on a send failure instead of rolling back

`NotifyOrganizationFollowersService#dispatch_immediate` inserts the sent-marker (`OrgNotificationDelivery`) and only THEN attempts the actual sends (web push, native push, SMS).

The marker insert and the sends cannot share one database transaction, because the sent-marker lives in the primary database while the actual channel sends are enqueued as jobs into a SEPARATE Solid Queue database — two different SQLite files, so there is no single transaction that could wrap both. If a channel dispatch raises AFTER the marker was already written, the method deletes the marker it just inserted (in a `rescue` around the three sends) so a later job retry can attempt the sends again — without that cleanup, the send-once guard would permanently swallow a notification that never actually went out.

## Why the web push loop never uses PushNotificationSubscription.active alone

`#dispatch_immediate`'s web-push loop scopes to `.where(user_id: user.id)` on top of `.active`.

`PushNotificationSubscription.active` ALONE, with no user scope, would send to every subscriber in the entire system — a notification meant for one organization's followers must never fan out that way.

## Why enqueue_digest calls DigestOrgNotificationAggregator unconditionally

`#enqueue_digest` used to be wrapped in `return unless defined?(DigestOrgNotificationAggregator)` — a stub left over from before the aggregator class existed.

That silent guard would have dropped every daily/weekly follower's digest with no error at all if autoloading ever hiccuped for any reason. Referencing the constant directly, with no `defined?` guard, makes a genuinely missing constant raise loudly instead of silently discarding notifications.
