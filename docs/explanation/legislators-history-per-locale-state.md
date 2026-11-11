---
mode: explanation
summary: "Why the Legislators page records which locale each piece of History-tab state belongs to, instead of using plain boolean flags."
status: agent-extracted
related: []
---

# Legislators History state is tracked per locale

Everything the Legislators page (`app/frontend/pages/Legislators.tsx`)
believes about the History tab is really a belief about ONE jurisdiction, so
each piece of state records which locale it refers to and is read back by
comparing against the active locale's id.

Plain true/false flags stopped working once the locale switch became a
partial reload: the page no longer starts over, so a flag set while viewing
Baltimore stayed set after switching to Congress, and `history` is a server
prop that the switch does not always refresh. The mobile History section had
the same bug and the same fix.

The rule that History is not fetched again when its tab is reopened in the
same session still holds. It now applies per locale, which is what it always
meant.

## Why `requestHistory` is one path for both the first open and a retry

`onError` sets `historyFailedFor` rather than leaving `isHistoryLoading`
stuck at true forever after a network hiccup or a server error.

Each value records the locale that was in play when the request went out, so
an answer that arrives after the reader has switched away is filed under the
locale it was asked for and read back as not the current one, instead of
overwriting what is on screen now.

## Switching locale while History is open or closed

Switching locale with History open refreshes the history in the switch
itself (`LOCALE_SWITCH_PROPS_WITH_HISTORY`), so the new locale's history is
what arrives. Switching with History closed leaves the old locale's data
sitting in props, so everything the page believed about it is thrown away
and the next open asks the server again.

The per-locale ids recorded for History state name the locale being
switched TO, and they are set before the server has agreed to the switch.
If the switch is refused, `locale` stays on the old one, so every recorded
id names a locale that is not on screen and the whole History panel goes
quiet at once — no loading line, no error, no empty state, no sessions.
`Legislators.tsx`'s `handleLocaleChange` restores the pre-switch ids when
the switch is refused, which is what keeps the tab showing the locale that
is still in effect.

## Mobile: `LegislatorsListScreen`'s `historyRequestedFor`

`LegislatorsListScreen` (`mobile/src/screens/LegislatorsListScreen.tsx`)
remembers whether the History fetch has already been asked for, so opening
that segment again in the same session does not fetch twice. This is
separate from whether `history` has come back yet.

It stores the locale rather than a yes/no, because the question is about
one jurisdiction: having asked for Baltimore's history says nothing about
Congress. As a plain boolean it stayed true across a locale switch, so no
fetch happened and the segment kept showing the previous locale's entries. Keeping the locale means the answer is worked out from what is
on screen and cannot drift out of step with it.

## Mobile: `useLegislators` and `LegislatorsListScreen` test notes

`mobile/__tests__/hooks/useLegislators.test.ts`: the voting history a
legislator holds belongs only to the locale it was fetched for. It used to
keep showing the previous locale's entries after the user switched, which
filed real records under the wrong government.

`mobile/__tests__/screens/LegislatorsListScreen.test.tsx`: the "already
asked" flag for History is now per-locale. It used to be a single boolean
that survived a locale switch, so reopening History kept showing the
previous locale's entries.
