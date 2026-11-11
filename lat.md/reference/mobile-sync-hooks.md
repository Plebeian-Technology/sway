---
lat:
  mode: reference
---

# Mobile sync hooks

These hooks keep mobile screen data current and track network reachability: useFocusedSync handles polling, subscriptions, and reconnects inline, while useReachability checks server reachability.

## useFocusedSync

`useFocusedSync` (`mobile/src/hooks/useFocusedSync.ts`) keeps a screen's data current, but only while that screen is visible.

- It rolls three tasks into one: a timer that refetches on a schedule, a live WebSocket subscription for score updates, and a listener that notices when the network returns. React Navigation's `useFocusEffect` shuts down all three when the screen leaves focus.

- Without that lifecycle hook, open screens would poll and hold score subscriptions indefinitely, wasting battery, network data, and memory.

- The cycle:

1. Screen becomes visible: the timer starts, the subscription opens, and the network listener attaches.
2. Screen is covered or tabs switch: the timer clears, the subscription closes, and the network listener detaches.
3. Screen returns: all three recreate from scratch so no stale timers fire twice.

- The subscription opens inside an async function immediately because token fetching is asynchronous. The `cancelled` flag prevents a late subscription from dangling if cleanup runs before token resolution finishes.

- `wasOfflineRef` persists in a ref across focus changes. NetInfo reports initial state on attach rather than a state change, so without the ref a screen hidden while offline would reset to false and miss the reconnect event. The hook handles reconnect logic inline without a separate hook.

## useReachability

`useReachability` (`mobile/src/hooks/useReachability.ts`) answers one question: can the app reach the server right now? This is the React Native version of `app/frontend/hooks/useReachability.ts`.

- It performs two concurrent checks. Every 30 seconds it pings `/up` with a 3-second HEAD request, while also listening for immediate NetInfo state changes.

- NetInfo reports the moment the connection drops.
- Periodic pings confirm whether the server is reachable when device status is inaccurate (for captive portals or unroutable networks).

- Return values match the web hook contract so `useOfflineCache` works identically on both platforms.

- `isResolved` stays false until the first probe or network event completes. An offline banner displays only when `!isOnline && isResolved` to avoid flashing during tab switches. Blocking writes treats unresolved status as offline.

- `isOnline` initializes to false so airplane mode does not display active vote buttons before the initial probe completes. The first successful probe or connected status turns it true.

- When NetInfo reports a dropped connection, the hook accepts it immediately. When NetInfo reports a restored connection, the hook verifies reachability with a ping first.
