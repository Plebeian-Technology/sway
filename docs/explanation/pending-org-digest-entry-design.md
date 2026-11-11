---
mode: explanation
summary: "Explains why PendingOrgDigestEntry is a durable database queue with plain-integer references, and why its cadence value is validated as defense-in-depth against a silently dropped digest."
status: agent-extracted
related: []
---
<!-- vale Vale.Spelling = NO -->

# Why PendingOrgDigestEntry is shaped the way it is

`PendingOrgDigestEntry` is a durable queue row for a pending digest
notification. `DigestOrgNotificationAggregator.enqueue` writes one when
`NotifyOrganizationFollowersService` routes a follower to a daily or
weekly digest instead of an immediate send; `.dispatch_period` deletes it
once that digest has actually been sent. Because the rows live in the
database rather than in memory or a job queue, they survive restarts of
the production server — a single Raspberry Pi that does restart.

`org_id` and `bill_id` are stored as plain integers, with no database
foreign key, because these are short-lived queue rows always deleted after
dispatch — there's no need to pay for referential-integrity enforcement on
a row that outlives the record it references for, at most, a dispatch
cycle.

## Why CADENCES is validated as defense-in-depth

`NotifyOrganizationFollowersService`, the only enqueuer, only ever writes
`"daily"` or `"weekly"` into `cadence`. The `CADENCES` inclusion validation
exists anyway, because the database column only enforces `NOT NULL` — a
typo or an un-cast value upstream would otherwise `create!` successfully
and then simply never match `.dispatch_period`'s `where(cadence:)` filter,
silently dropping that entry's digest and leaking an orphan row that
nothing ever cleans up. The inclusion and presence validations here close
that gap at the one place every write passes through.

## Why `DigestOrgNotificationAggregator.dispatch_period` selects with no `created_at` window

`.dispatch_period` selects ALL pending rows for a cadence with no
time-window filter at all, then deletes every dispatched row after
sending — that deletion IS what marks a row as handled. A query windowed
to, say, "created in the last 24 hours" would permanently strand any row
not consumed within exactly that window: if the Pi misses its scheduled
23:00 run, or the run starts late, a windowed query would silently drop
the very rows the late run exists to catch, breaking the promise that no
pending change is ever lost.

## Why `.dispatch_period` deletes a user's rows BEFORE attempting to send anything

For each follower, `.dispatch_period` deletes that user's pending rows
FIRST, then attempts the actual sends (web push, native push, SMS). The
rows live in the primary database, but the SMS/push jobs are enqueued
into a SEPARATE Solid Queue database, so no single transaction can make
"send, then delete" atomic. Deleting first means a crash between the
delete and the enqueue drops one low-stakes daily/weekly summary
(at-most-once delivery) — accepted as better than the alternative, where
a job re-dispatch after a crash sends a duplicate, billable SMS
(at-least-once delivery). `limits_concurrency` on `DailyOrgDigestJob` and
`WeeklyOrgDigestJob` (see
[the org-digest jobs concurrency doc](org-digest-jobs-concurrency.md))
additionally stops a scheduled run and a manual trigger from overlapping
at all, which is the other half of what keeps this delete-first choice
safe.

A destroyed user (no foreign key catches that) or a user whose master
gate has since been switched off is never delivered to — but their rows
were already claimed and deleted in the step above, so nothing stale is
left behind for a later run to find. The same applies when every
referenced organization has since been deleted (also no foreign key): the
rows were already claimed, so the digest is simply skipped rather than
sent with nothing to say.

## Why the master gate is re-checked in `dispatch_period`

Delivery mirrors `dispatch_immediate` in `NotifyOrganizationFollowersService`:
web push (only this user's subscriptions), native push (`kind:
org_position_taken`), SMS (only when the user opted into SMS and verified
their phone). Master gate: the user's `org_position_taken`
`NotificationPreference` must be enabled. Entries are already filtered
upstream to non-muted change types, but the master gate is re-checked here
as a second line of defense.
