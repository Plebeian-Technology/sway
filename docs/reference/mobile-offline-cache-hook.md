---
mode: reference
summary: The read-cache-then-fetch cycle useOfflineCache runs, when it refetches, and what it deliberately never does.
status: agent-extracted
related: []
---

# useOfflineCache hook

`useOfflineCache` (`mobile/src/hooks/useOfflineCache.ts`) shows the copy
already saved on the phone at once, then quietly fetches a fresh one. It
works for any list, over the app's SQLite database.

## The cycle

Runs the first time the hook is used, and again whenever anything in the
caller's `deps` array changes:

1. **`cache.get()`** — read from SQLite immediately, so the screen shows the
   last data seen instead of waiting on the network. If nothing is saved,
   the screen shows an empty list until step 2 arrives.
2. **`fetcher()`** — fetch over the network, but only once the hook knows it
   is actually online. A freshly launched app usually starts out believing
   it is offline, because the check that pings the server's `/up` address
   has not answered yet (it can take up to 3 seconds). The "when it fetches"
   section below covers that case.
3. **`cache.set()`** — write the fresh rows back into SQLite so the next
   launch paints instantly. This write happens even if the screen has
   already gone away; only the on-screen update is skipped in that case.

## When it fetches

- The first time the hook runs.
- Whenever anything in `deps` changes — for example, the user picks a
  different city or state.
- The moment the connection returns after being down: the launch-time check
  finishes, the phone regains signal, a hotel wifi sign-in page is cleared,
  and so on.
- Whenever the screen calls the returned `refresh()` itself: pull to
  refresh, a nudge from the live score connection, and similar triggers.

## What it deliberately does not do

- It does not refetch when a screen comes back into view. Wrap it in
  `useFocusEffect` in the screen if that behavior is wanted.
- It does not poll on a timer. Add a timer plus `refresh()` for that.
- It does not retry after a failure. The saved data stays on screen, and
  `error` is handed back so the screen can show a message.

## Writes must check `isOnline` first

Anything that saves data — voting, changing settings — must stop early when
offline. `assertOnlineForWrite` (bottom of the same file) throws when
`isOnline` is false. Sway does not queue such changes to send later; the
user is told plainly that they need a connection to make that kind of
change. Call it before anything that saves data: casting a vote, changing
settings. Do not use it before merely reading data.

## `isResolved`

True only once the hook actually knows whether it is online — the ping to
the server has answered, or the phone has reported its network state. Show
an "you are offline" banner only when `!isOnline && isResolved`, so
switching tabs does not flash a banner during the second or two before it
knows.

## Internal state notes

`data` starts as `null`, not `[]`, so a screen can tell "still loading, we
have never seen anything" apart from "we asked and there genuinely is
nothing". Those mean different things: the bills list shows a spinner for
`null` and a "nothing here" card for an empty list.

`loading` starts `true` because the cycle begins the instant the hook runs
— it reads the cache, and probably fetches too. Starting at `false` would
leave a split second where the screen claims to be loaded and empty before
the work even starts, which shows up as a flicker when JavaScript is busy.

`mountedRef` starts `true` because it is set before any cleanup can run.
The checks inside `refresh()` must see "still on screen" on the very first
render. The effect that owns it sets it back to `true` each time the screen
appears and to `false` when it goes away.

The first `useEffect` (over `deps`) leaves `refresh` out of its dependency
list on purpose: `refresh` is rebuilt every time the online flag flips, and
including it would make a freshly launched app fetch twice for no reason.
Coming back online is handled by the next effect.

## Fetching the moment the connection returns

A freshly launched app usually starts out looking offline, because the
ping to the server's `/up` address has not answered yet. The `deps` effect
will not run again by itself once that changes — nothing in `deps`
changed — so a separate effect refetches at the exact moment the network
becomes usable.

That effect's starting value, `wasOnlineRef`, is whatever the current
online flag says, not a hard-coded `false`. Otherwise a hook that starts up
after the network check has already finished would see a fake
"offline to online" jump and fetch on its first render. The fetch should
only happen on a real change.
