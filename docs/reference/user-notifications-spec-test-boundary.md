---
mode: reference
summary: "What spec/system/user_notifications_spec.rb fakes inside the browser versus what runs for real against the Rails backend."
status: agent-extracted
related: []
---

# User notifications spec: faked vs. real

`spec/system/user_notifications_spec.rb` is a browser test for the
notifications page. It fakes the browser's push-notification APIs but drives
the real Rails stack underneath them.

## Faked inside the browser

- `window.Notification.requestPermission()` answers `"granted"`.
- `navigator.serviceWorker.register()` hands back a pretend registration.
- `pushManager.getSubscription()` and `subscribe()` hand back a made-up
  `PushSubscription` with an invented endpoint, `p256dh`, and `auth`.

## Real

- The Rails controllers (`notifications#index`,
  `push_notification_subscriptions#create` and `#destroy`).
- The form's post and delete going out and coming back through a redirect.
- `PushNotificationSubscription` rows saved in the database.
