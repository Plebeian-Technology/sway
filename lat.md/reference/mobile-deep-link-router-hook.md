---
lat:
  mode: reference
---

# useDeepLinkRouter hook

`useDeepLinkRouter` (`mobile/src/hooks/useDeepLinkRouter.ts`) opens the screen a push notification is about, when someone taps it.

- It listens for notification taps and reads the small bundle of data the server attached to the notification (`SendNativePushJob` builds it through `NativePushDispatcher`):

```
{ kind, bill_id?, legislator_id?, deep_link? }
```

## Which screen wins

Precedence mapping establishing navigation target priority when multiple deep link parameters are present.

- `bill_id` → App > Bills > BillDetail
- `legislator_id` → App > Legislators > LegislatorDetail
- `deep_link` is set aside for future URL-style paths. When the app is
  opened from cold by a link, React Navigation's own linking config
  handles it.

- If the navigator is not mounted yet, this does nothing. React Native mounts `NavigationContainer` after `BootstrapProvider`'s first render, so there is a brief moment with nothing to navigate.

## Why the navigation call is retyped through unknown

The chain of screen types (`RootParamList` → `AppDrawerParamList` → `BillsStackParamList`) is not visible to `NavigationContainerRef` when you navigate with a nested screen/params object.

- The chain of screen types (`RootParamList` → `AppDrawerParamList` → `BillsStackParamList`) is not visible to `NavigationContainerRef` when you navigate with a nested screen/params object, so TypeScript cannot check this call and it is told to step aside.
