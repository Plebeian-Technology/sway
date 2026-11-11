---
lat:
  mode: explanation
---

# Push subscriptions in the browser

Enabling push notifications joins two pieces of state: a `PushSubscription` held by the browser's service worker, and a row on the server that the Notifications panel lists. The order they are changed in sets what a failure leaves behind.

## Cross-referencing this device's subscription

[[app/frontend/hooks/notifications/usePushSubscription.ts#usePushSubscription]] reads the current endpoint out of the service worker and matches it against the deferred `subscriptions` prop, so "this device" is a comparison rather than a stored value.

A `cancelled` flag guards the effect, because `getRegistration` and `getSubscription` can resolve after the panel has unmounted, where a `setState` has no effect.

## Why the public key is stripped of padding but not of whitespace

The VAPID public key reaches the browser through a JavaScript string literal in
the layout, with its base64 padding removed.

Stripping the padding characters is what the web-push library documents. It
does not remove a trailing newline, and a newline that survives lands inside
the string literal and raises a syntax error, which breaks push subscription
without any message naming push. A key stored with a stray newline therefore
fails in a place that looks unrelated to the key.

## Why the subscribe form transforms its data

`saveSubscription` passes the endpoint and keys through `transform()` rather than `setData`.

Inertia v3 syncs a form's data through a ref, so a submission made in the same tick as a `setData` can still carry the previous values. `transform()` runs at request-build time and therefore always sees the current ones.

## Why registration races against a timeout

`registerServiceWorker` races `getRegistration()` against a three-second timeout, the same pattern `useLogout` uses.

The PWA service worker is registered at startup by `registerPWA()` in `entrypoints/application.tsx`, and `navigator.serviceWorker.ready` never rejects, so a wait on it has no upper bound.

## Why activation is awaited before subscribing

`pushManager.subscribe()` needs an active service worker, and a click on Enable can land while a freshly registered one is still installing.

That call then raises an `AbortError` naming the missing active worker, so the hook waits for the installing or waiting worker to reach the `"activated"` state, capped at five seconds. The `statechange` listener is added with an `AbortController` signal, so it is removed whether the timeout wins or another exit path aborts first; without the signal it stayed attached after a timeout.

## Why Enable discards the browser's existing subscription

Enable unsubscribes any `PushSubscription` the browser already holds and subscribes again with the current VAPID public key, so every saved subscription is bound to the key the server signs with.

A subscription is bound to the application server key it was created with, and the push service accepts a message for its endpoint only when it is signed with the matching private key. After the key pair is rotated, the browser still holds a subscription made with the old public key, and `getSubscription()` returns it with no sign that it is dead. Reusing it would post that endpoint to the server again, which would then record a subscription the push service rejects on every send. The same holds when the server row was deleted while the browser kept its subscription: the panel offers Disable only when a matching row exists, so Enable is the one control left, and it must not re-save what the browser already had.

If `unsubscribe()` rejects, the hook reports an error and saves nothing. The Push API rejects a `subscribe()` call whose key differs from that of a subscription still in place, and saving the old subscription instead would bring back the dead row this path exists to prevent.

## Why the browser unsubscribes only after the server delete

The server row is what the "Other devices" list reads, so the disable path sends the DELETE first and calls `unsubscribe()` from its `onSuccess`.

The earlier order unsubscribed the browser first, and the DELETE carried no `onError`. A server failure then left the row marked `subscribed` while the endpoint it names no longer accepted a push, and `onSuccess` never ran, so the panel went on showing the device as enabled until the page was reloaded by hand. With the DELETE first, a failure leaves both sides subscribed, which needs no rollback, and `onError` reloads the `subscriptions` prop so the panel shows what the server holds. `saveSubscription` has always passed `onError` for the same reason.

## Why subscription redirects name the Push tab explicitly

[[app/controllers/notifications/push_notification_subscriptions_controller.rb#PushNotificationSubscriptionsController]] redirects to [[app/controllers/notifications_controller.rb#NotificationsController]]'s push tab constant so returning to the push panel is an explicit server contract.

Without an explicit tab parameter, the redirect drops query parameters and returns to `/notifications`. [[app/frontend/pages/Notifications.tsx#Notifications]] falls back to the Push tab when push support is detected, which matches the condition under which subscribing or unsubscribing runs, but relying on that fallback leaves the landing tab dependent on client-side default selection luck. Passing the tab parameter explicitly ensures the browser returns to the Push panel across both subscribe and unsubscribe operations, preserving the URL tab parameter described in [[notifications-tab-url#The Notifications tab in the URL]].
## Why activation confirmations target only the requesting subscription

Re-enabling or reposting an existing push subscription sends the activation confirmation exclusively to that subscription endpoint, preventing unintended broadcasts to other devices or accounts.

When an existing subscription is re-enabled or posted again in `[[app/controllers/notifications/push_notification_subscriptions_controller.rb#Notifications::PushNotificationSubscriptionsController#create]]`, the controller passes the resolved subscription record directly to `[[app/services/sway_push_notification_service.rb#SwayPushNotificationService]]`. In `[[app/services/sway_push_notification_service.rb#SwayPushNotificationService#get_subscriptions]]`, omitting this parameter causes the service to fall back to all active subscriptions in the database, broadcasting the activation confirmation across unrelated users and additional devices. Supplying the specific subscription restricts delivery strictly to the caller's endpoint.

## Why concurrent subscription creates recover from RecordNotUnique

[[app/controllers/notifications/push_notification_subscriptions_controller.rb#PushNotificationSubscriptionsController#create]] rescues uniqueness conflicts by locating the winning row and marking it subscribed.

The database enforces one row per user and endpoint, so two overlapping requests from the same browser can race past the initial lookup. Updating the row that won the race leaves both requests converged on an active subscription instead of surfacing an error on the second click.
