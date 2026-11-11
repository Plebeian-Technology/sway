---
mode: explanation
summary: "Why Api::V1::NotificationsController#test_push resolves the target device from push_token instead of the most-recently-active device, and why it bypasses the notification-preference gate with kind: test_push."
status: agent-extracted
related: []
---

<!-- vale Vale.Spelling = NO -->

# `Api::V1::NotificationsController#test_push` design notes

## Why the request body carries `push_token`

The mobile Push tab needs the test push to land on THIS device, not the
most-recently-active one. A user with several devices (a work iPad and a
personal phone) would otherwise see the test push fire on a different
device than the one they tapped "Send test" on. Resolving the device
through `current_user.user_devices.with_push.find_by(push_token:)` closes
both that bug and a cross-user token-probing hole: the same 404 answers
both "not owned by this user" and "no active push-capable device matches",
so a caller cannot tell which and cannot probe which tokens exist.

## Why the job runs with `kind: "test_push"`

`SendNativePushJob` has an explicit `kind: "test_push"` bypass branch that
runs BEFORE its notification-preference gate. A user who has turned off
every notification preference can still receive their test push —
otherwise the feature would silently do nothing and confuse the user
testing it.

## Mobile: only `usePushToken` sends the token to the server

`NotificationPrefsScreen` (`mobile/src/screens/NotificationPrefsScreen.tsx`)
must NOT call `getExpoPushTokenAsync`. It calls
`Notifications.getDevicePushTokenAsync` only once permission has been
granted, to get this device's token for the test-push request.
`usePushToken`, mounted at the top of the app, stays the only thing that
sends the token to the server.

`PushTab`, a component used only in this file, asks
`useDeviceRegistration` whether the server has really registered this
device. `usePushToken`, mounted at the top of the app, is what sends the
token up; this tab only READS the resulting status and shows the button.

## Mobile: why `NotificationPrefsScreen.test.tsx` mocks `useDeviceRegistration`

The "Send test" button only shows once the server confirms this device is
registered for push, and `useDeviceRegistration` is what reports that.
Mocking it lets each test move `registrationStatus` between "registering"
and "registered", and supply the `deviceToken` that gets sent in the
test-push request body.
