---
lat:
  mode: explanation
---

# Test push device targeting

Test push notifications verify device delivery and credential registration without requiring external push services during automated testing.

The notification testing architecture verifies device registration status and payload delivery using targeted device tokens.

## Why NotificationPrefsScreen test mocks DeviceRegistrationContext

The test harness mocks `useDeviceRegistration` to simulate push registration lifecycles without requiring native device push hardware.

The push test action on `NotificationPrefsScreen` renders only after the backend confirms device registration. Mocking the registration hook allows test suites in [[mobile/__tests__/screens/NotificationPrefsScreen.test.tsx]] to transition `registrationStatus` between pending and registered states and verify dispatch payloads.

## Why the request body carries push_token

Test push requests supply explicit device push tokens so test notifications target the specific initiating device.

When a user owns multiple registered devices, delivering test notifications to the most recently active device would send notifications to an unexpected device. Resolving the target via `current_user.user_devices.with_push.find_by(push_token:)` ensures notifications arrive on the requesting hardware. Returning identical 404 responses for nonexistent tokens and unowned devices prevents cross-user token probing.

## Why the job runs with kind: "test_push"

Test notifications execute with `kind: "test_push"` to bypass preference filtering and deliver verification messages.

`SendNativePushJob` evaluates an explicit `kind: "test_push"` bypass before enforcing notification preference filters. This prevents test notifications from being silently discarded when users have disabled standard notification categories.

## Mobile: only usePushToken sends the token to the server

Device push token registration is restricted to `usePushToken` while preference screens only read tokens for test dispatches.

`NotificationPrefsScreen` (`mobile/src/screens/NotificationPrefsScreen.tsx`) avoids calling `getExpoPushTokenAsync`. It invokes `Notifications.getDevicePushTokenAsync` solely after permission grant to retrieve the token for test-push requests. `usePushToken`, mounted at the application root, serves as the exclusive mechanism that submits device tokens to backend endpoints.

`PushTab` queries `useDeviceRegistration` to verify server registration state. `usePushToken` manages transmission while `PushTab` reads status and renders the action trigger.

