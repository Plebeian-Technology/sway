---
lat:
  mode: explanation
---

# Mobile push registration gating

`DeviceRegistrationContext` (`mobile/src/state/DeviceRegistrationContext.tsx`) tracks whether the server has confirmed this device's push registration, separately from whether the OS has granted notification permission.

## Why the gate is server confirmation, not OS permission

The push section of `NotificationPrefsScreen` MUST only offer its "Send test notification" button once the SERVER has confirmed registration, not merely because the operating system granted permission.

Someone who has just said yes, while `PATCH /api/v1/devices/push_token` is still in flight or has failed, sits in `granted-pending-registration`; a test send then would come back 404 `no_device`, because the server holds no push token for that device yet.

`usePushToken`, mounted at the top of the app, is what performs the PATCH. `DeviceRegistrationContext` EXPOSES the result, so the push section can read it through `useDeviceRegistration()`.

The rule holds here too: only `usePushToken` calls `getDevicePushTokenAsync`. Everyone else reads the `deviceToken` it leaves behind.
