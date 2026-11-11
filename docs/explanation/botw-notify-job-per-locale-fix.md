---
mode: explanation
summary: "Why OnBillBecomesBotwNotifyUsersJob notifies each locale's un-notified Bill of the Week separately instead of picking one bill across all locales."
status: agent-extracted
related: []
---

<!-- vale Vale.Spelling = NO -->

# Why the BotW notify job iterates per locale

One Bill of the Week PER LOCALE per day is the schema contract (unique
index on `(scheduled_release_date_utc, sway_locale_id)` — `bill.rb`). The
old `.find(&:notifyable?)` picked a single bill across ALL locales, so on
any day when two locales scheduled a BotW, only the one with the lowest id
was ever notified. `OnBillBecomesBotwNotifyUsersJob` notifies each locale's
un-notified BotW instead, with a per-bill rescue (same pattern as
`RefreshLegislatorsCacheJob`) so one locale's failure cannot block the
others.

## Why native push fan-out uses one joined query

`#fan_out_native_push`'s single joined query replaces an old nested
`User.find_each` → `user_devices.find_each` pattern, which cost one extra
query per user.

## Web push vs native push fan-out

Web push fan-out is triggered by `BillNotification#after_create_commit
:notify` (via `SwayPushNotificationService`) when this job creates the
`BillNotification` row. This job additionally fans out NATIVE push (FCM
for Android, APNs for iOS) itself, by enqueueing `SendNativePushJob` for
each active push-enabled `UserDevice` whose user has the
`botw_announcement` preference turned on.
