---
lat:
  mode: explanation
---
# Why the featured bill notify job iterates per locale

One Bill of the Month per locale per day is the schema contract. `NotifyBillOfTheMonthUsersJob` notifies each locale's un-notified featured bill separately with a per-bill rescue so one locale's failure cannot block the others.

The unique index on `(scheduled_release_date_utc, sway_locale_id)` in `bills` guarantees at most one featured bill per locale each day. Picking a single bill across all locales would cause only the lowest ID to be notified when multiple locales schedule a bill on the same date.

## Why native push fan-out uses one joined query

Native push fan-out queries active push devices and notification preferences in a single joined database query.

`#fan_out_native_push`'s single joined query replaces an old nested `User.find_each` to `user_devices.find_each` pattern, which cost an extra query per user.

## Web push vs native push fan-out

Web push and native push fan-out are dispatched through separate pathways when a featured bill is announced.

Web push fan-out is triggered by `BillNotification#after_create_commit :notify` via `SwayPushNotificationService` when this job creates the `BillNotification` row. This job additionally fans out native push (FCM for Android, APNs for iOS) itself, enqueueing `SendNativePushJob` for each active push-enabled `UserDevice` whose user has the `botm_announcement` preference enabled with payload kind `botm_announcement`.
