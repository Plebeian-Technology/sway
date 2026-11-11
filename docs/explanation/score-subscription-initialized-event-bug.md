---
mode: explanation
summary: "Explains why useScoreSubscription tracks isAwaitingScoreUpdate instead of an isSubscribed flag, after an actioncable event-name mismatch bug."
status: agent-extracted
related: []
---

# Why useScoreSubscription has no `isSubscribed` flag

`useScoreSubscription` (`app/frontend/hooks/useScoreSubscription.ts`) is an
event-driven "awaiting a score update" flag. An earlier version of the hook
had an `initialize()` callback meant to flip an `isSubscribed` flag to
`true` once the ActionCable subscription was ready. That callback never
ran: `@rails/actioncable`'s JS client fires an event named `initialized`
(not `initialize`), so the callback name was silently wrong and the flag
stayed `false` forever. That broke the "Waiting for the latest score
update…" message on `BillContent`/`BillChartsPanel`, which depended on it.

The flag consumers read today, `isAwaitingScoreUpdate`, sidesteps the dead
callback entirely. It is `true` from the moment a `refresh_scores` message
arrives until the resulting `router.reload()` finishes, and needs no
subscription-readiness signal at all.
