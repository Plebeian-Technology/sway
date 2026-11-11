---
lat:
  mode: explanation
---

# Api::V1::DevicesController.update_push_token design notes

Why Api::V1::DevicesController rate-limits push-token updates by a hashed bearer token, and why it revokes a stolen push token from its previous owner.

## Why the rate limit hashes the bearer token

30 requests per minute per bearer token stops push-token churn from flooding the `Rails.cache`-backed rate-limit store.

The limiter hashes the bearer with `Digest::SHA256` before using it as the rate-limit key, so cache backends and instrumentation never see the raw `Authorization` header — `filter_parameters` does not scrub cache keys, so the hash is the only thing standing between the raw token and anything that inspects the cache.

## Why push token updates prefer the bearer token's bound device

[[app/controllers/api/v1/devices_controller.rb#DevicesController#update_push_token]] resolves the target [[app/models/user_device.rb#UserDevice]] from the calling bearer token's bound device (`current_api_key.user_device`) when active, before falling back to the user's most recently seen active device.

When a user is signed in on two mobile devices at once, resolving by `last_seen_at` alone lets a background token registration from the older session overwrite the newer device's push token and revoke the older session's own row through the colliding-token cleanup. Preferring `current_api_key.user_device` binds the update to the exact device that authenticated the request while keeping the `last_seen_at` fallback for legacy unbound keys.

## Why another user's device is revoked when a push token moves

A push token belongs to the physical device, not the user: a phone's APNs/FCM token follows whichever account is currently signed in.

Any other user's active row already holding this token is revoked in the same transaction, so the partial unique index (`push_token WHERE revoked_at IS NULL`) does not reject the write when a device changes hands between accounts.

## Why CleanupRevokedDevicesJob exists as a safety net, not the primary path

The PRIMARY revocation path is `SendNativePushJob`'s rescue of `NativePushDispatcher::DeviceNotRegisteredError`.

The PRIMARY revocation path is `SendNativePushJob`'s rescue of `NativePushDispatcher::DeviceNotRegisteredError`, which calls `device.revoke!` when FCM/APNs reports UNREGISTERED / Unregistered / BadDeviceToken on a real send attempt.

`CleanupRevokedDevicesJob` is a recurring SAFETY NET that keeps `UserDevice.revoked_at` in line with `ApiKey.expires_at` — if a device's bearer `ApiKey` has expired but `revoked_at` was never set (a race, a crash, an orphaned row), this job catches it.

IMPORTANT: this job does NOT revoke idle devices. Devices with no `api_keys` or with fresh `api_keys` are LEFT ALONE — an idle device belongs to a valid user who has not opened the app in a while, and revoking it would silently break push delivery. A future sweep of devices idle more than 90 days is a deferred enhancement (tracked separately).

## Why SendNativePushJob only revokes on a real delivery receipt

`SendNativePushJob` sends one native push notification to one device, checking before sending, in order.

`SendNativePushJob` sends one native push notification to one device, checking before sending, in order: the device exists and is not revoked, the device has a non-blank `push_token`, and the user has the matching `NotificationPreference` enabled.

On `NativePushDispatcher::DeviceNotRegisteredError` (raised when FCM/APNs answers a real send attempt with UNREGISTERED / Unregistered / BadDeviceToken) the device is auto-revoked. Revocation happens only on that delivery receipt — a device that is merely dormant is never revoked here.

## Why a test push bypasses the notification-preference gate

A user-initiated test send (`payload[:kind] == "test_push"`) bypasses the preference gate.

A user who has disabled every notification preference must STILL receive their test push — otherwise the "Send test notification" button silently does nothing, and the user can't tell whether push works at all.

## usePushToken, the mobile client hook

`usePushToken` (`mobile/src/hooks/usePushToken.ts`) signs the device up to receive push notifications.

When it starts for a signed-in user:

1. It asks the phone for permission to send notifications.
2. When permission is granted, it retrieves the device's own push address with
   `Notifications.getDevicePushTokenAsync()`. On Android that is a
   Firebase Cloud Messaging registration token; on iOS it is an Apple Push
   Notification service device token, written in hex.
3. It sends the address to the server via `PATCH /api/v1/devices/push_token` with `{
   push_token, platform, app_version }`. If the request fails, the hook records `registrationStatus: "failed"` and awaits the next launch or token rotation.
4. It listens for the phone replacing that address and sends the new one.

It never requests an Expo push token: Sway's own server talks straight to Firebase and to Apple, with no Expo relay in between. The test at `__tests__/hooks/usePushToken.test.ts` checks that the Expo token method is never called.

The Authorization header and the push token itself are stripped out of the trail of events sent to Sentry, our error reporter, by `scrubPushTokenBreadcrumb` in `observability/sentry.ts`.

The hook checks what permission it already has before asking for it. Once someone has said no, the phone will not show the prompt again — but they may have since turned notifications on in Settings, in which case permission is already granted and the hook carries on without prompting. It only asks when the phone says asking is still allowed.

`useDeviceRegistrationWriter` reports how sign-up went, so the Push settings tab can keep its "Send test" button switched off until the server has confirmed the device, not merely until the phone granted permission. Because `setRegistration` has a stable identity across renders, the effect depends only on `isAuthenticated`. Outside the provider this writer does nothing, so the hook is safe to use before the provider exists, or without it.
