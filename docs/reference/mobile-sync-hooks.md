---
mode: reference
summary: The mobile network/sync hook family — useActionCableReconnect, useFocusedSync, useReachability, useScoreSubscription, and usePoll — what each does and how they compose.
status: agent-extracted
related: []
---

# Mobile sync hooks

These hooks are how a mobile screen keeps its data current: a live
WebSocket push, a polling timer as backup, and network-status watching so a
dropped connection recovers on its own.

## useActionCableReconnect

`useActionCableReconnect` (`mobile/src/hooks/useActionCableReconnect.ts`) is
the mobile version of the web hook with the same name. It watches the
phone's network status (through NetInfo) and, the moment a dead connection
comes back, calls `onReconnect` so the screen can reload its data. Reopening
the live WebSocket is not its job: ActionCable, the Rails WebSocket layer,
reconnects itself.

The `wasOffline` flag stops it firing on the very first status update.
NetInfo reports the current state as soon as you start listening, and that
first report is not a change — it only cares when the connection actually
flips from off to on.

## useFocusedSync

`useFocusedSync` (`mobile/src/hooks/useFocusedSync.ts`) keeps a screen's
data current, but only while that screen is the one you are looking at.

It rolls three things into one: a timer that refetches on a schedule, a
live WebSocket subscription for score updates, and a listener that notices
when the network comes back. All three are hung off React Navigation's
`useFocusEffect`, so all three are shut down the moment the screen is no
longer on top.

Without that, every bill screen you opened would keep polling the network
and keep an open score subscription forever after you moved on — burning
battery and data, and piling up unreleased memory the deeper you browsed.

The cycle:

1. Screen becomes visible → the timer starts, the subscription opens, and
   the network listener is attached.
2. Screen is covered or you switch tabs → the timer is cleared, the
   subscription is closed, and the network listener is removed.
3. Screen comes back → all three are created again from scratch. The old
   timer is guaranteed gone, so nothing fires twice.

The subscription is opened inside an async function that runs immediately,
because fetching the login token is asynchronous. The `cancelled` flag
covers the gap: cleanup runs the instant the screen is hidden, and without
the flag a subscription that finished opening after that point would be
left dangling.

`wasOfflineRef` is kept in a ref so it survives the screen being hidden and
shown again. NetInfo reports the current network state as soon as you start
listening, which is not a change of state. Without the ref, a screen hidden
while offline and reopened while still offline would reset this to false
and then miss the moment the connection actually returns. The standalone
`useActionCableReconnect` hook does the same thing.

## useReachability

`useReachability` (`mobile/src/hooks/useReachability.ts`) answers one
question: can the app reach the server right now? This is the React Native
version of `app/frontend/hooks/useReachability.ts`.

It does two things at once. Every 30 seconds it pings the `/up` address
with a HEAD request, giving up after 3 seconds. It also listens to the
phone's own network status for instant news. Together:

- The phone reports the moment the connection actually drops.
- The ping proves, twice a minute, whether the server is really reachable,
  for when the phone's opinion is wrong — hotel wifi that needs a sign-in,
  networks with no route to the server, and so on.

The values it returns are shaped exactly like the web hook's, so
`useFreshness` and `useOfflineCache` can be written once and work on both.

`isResolved` is false until there is an answer, either from the first ping
or from the phone. Show an "you are offline" banner only when `!isOnline &&
isResolved`, so switching tabs does not flash one during the three seconds
where the hook genuinely does not know. Blocking writes ignores this flag
on purpose: not knowing is treated as offline, which is the safe side to be
on.

`isOnline` starts at `false`. Otherwise an app opened in airplane mode
would show working vote buttons for the three seconds it takes the first
ping to give up. The first successful ping, or the phone reporting a
connection, turns this true.

When NetInfo reports the connection is gone, the hook trusts it straight
away. When it reports the connection is back, the hook checks with a ping
first — the phone is sometimes wrong about that.

## useScoreSubscription

`useScoreSubscription` (`mobile/src/hooks/useScoreSubscription.ts`) opens a
live connection so the server can tell this screen when vote totals change.

The server sends one kind of message: `{ action: "refresh_scores" }`. The
website receives the same one — see `app/channels/score_channel.rb` and
`ScoreUpdaterService`. When it arrives, this hook calls `onRefresh()` and
the screen fetches the bill again.

Setting up is asynchronous, because fetching the login token and opening
the connection both take time. The `active` flag covers the race where the
screen disappears while that is still happening: on a slow network the
subscription can finish being created after the cleanup has already run.

This is the low-level piece. Screens normally use `useFocusedSync` instead,
which bundles this together with polling and reconnect handling and shuts
all three down when the screen is no longer visible.

`isSubscribed` is flicked off and straight back on when a refresh message
arrives, so a screen watching that flag gets a chance to replay an
animation or show a spinner. The web hook does the same.

## usePoll

`usePoll` (`mobile/src/hooks/usePoll.ts`) calls `onPoll` every `ms`
milliseconds for as long as the screen using it is on screen.

It matches the website's `usePoll` (`app/frontend/hooks/usePoll.ts`). Both
are a safety net: scores normally arrive as live pushes over a WebSocket,
and this timer catches whatever the push misses. Callers use 15000
milliseconds.

The timer is cleared when the screen goes away, and also whenever the
interval or the callback changes, so timers never pile up on top of each
other.
