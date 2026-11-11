---
mode: reference
summary: Contract for useNotificationPrefs — the optimistic toggle-and-revert behavior, the four preference keys, and the server's defaults.
status: agent-extracted
related: []
---

# useNotificationPrefs hook

`useNotificationPrefs` (`mobile/src/hooks/useNotificationPrefs.ts`) is which
notifications the user wants.

It reads them from `GET /api/v1/notification_preferences` and gives you a
toggle that flips a switch on screen first and tells the server after:
`PATCH /api/v1/notification_preferences/:key { enabled }`.

## How it behaves

- On first use it loads the settings; loading stays true until the first
  answer arrives.
- Toggling flips the switch on screen at once, then sends the change. If
  the server refuses, the switch flips back.
- `refresh` re-reads everything from the server, used when the app returns
  to the foreground.

The server's own defaults: the Bill of the Week announcement is on, the
other three are off. Show all four switches even if the server leaves one
out — older accounts may not have every setting stored.

## Why `toggle` reads the previous value out of live state

`toggle` reads the old value out of the live state, and only for this one
switch. If it instead remembered a whole copy of the settings from when the
tap happened, undoing a failure would also wipe out any other switch the
user flipped in the meantime, or anything a `refresh()` brought in. Undo
touches one switch only.
