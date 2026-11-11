---
mode: explanation
summary: "Why Bill.tsx and BillOfTheWeek.tsx include the specific props they do in their POLLING_PROPS score-sync lists."
status: agent-extracted
related: [docs/reference/partial-reload-prop-lists.md]
---

# Why Bill.tsx and BillOfTheWeek.tsx poll the props they do

Both pages pass a `POLLING_PROPS` list to `usePoll`, `useScoreSubscription`,
and `useActionCableReconnect`, which all call
`router.reload({ only: POLLING_PROPS })`. The web and mobile apps have a
written agreement to keep the poll interval at 15000ms — do not change it
on one page without changing it everywhere.

## Bill.tsx

`POLLING_PROPS` is `["bill_score", "organizations", "user_legislator_emails"]`.

`organizations` (the stances organizations take on this bill) is drawn on
this page but used to have no live update and no poll, so a newly approved
stance never showed up unless the reader reloaded. Adding it to the list
the score sync already uses gives it the same 15-second poll and the same
WebSocket path.

`user_legislator_emails` is on the list too, so the compose dialog's status
moves from pending to sending to sent on its own, with no reload.

`billPollingTuple.test.ts` is a tripwire against drift: the `POLLING_PROPS`
list on the Bill and Bill of the Week pages must keep `organizations`, so an
organization's stance on a bill updates by itself on the same rhythm as the
scores. The other half of the deal — the server actually sending
`organizations` on a partial reload — is checked in
`spec/requests/partial_reload_contracts_spec.rb`.

## BillOfTheWeek.tsx

`POLLING_PROPS` is `["bill", "sponsor", "organizations", "user_vote", "bill_score"]`.

`organizations` (drawn by `BillContent`) travels with the score sync, so a
newly approved stance appears without the reader reloading — same rationale
as `Bill.tsx`.

`bill`, `sponsor`, and `user_vote` are on the list as well. Unlike
`/bills/:id`, which bill this page is about is chosen and scheduled by an
admin, so it can change under a reader who is just sitting there. Leaving
`bill` off caused two problems:

- A locale with nothing featured drew the empty state and then never asked
  for a bill again, so a reader waiting for the admin to publish one had no
  way forward but a manual refresh — never an acceptable step in a workflow
  here.
- When the admin pointed the page at a different bill mid-session, the bill
  swapped while the sponsor, the reader's own vote, and the organization
  stances beside it still described the old one.

Everything this page draws follows from that single choice of bill, so it
all refreshes together. `Organization.tsx` works the same way and names its
whole set for the same reason.

## Legislators.tsx

`Legislators.test.tsx` pins the 15-second `usePoll` fallback and the list of
props `useScoreSubscription` refreshes on the Legislators page. The written
agreement above keeps the web and mobile apps refreshing at the same rate:
`usePoll(15000, { only: ["legislators"] })` with `useScoreSubscription`
watching the SAME list. Those tests hold those values in place — do not
change `15000` or the list without changing it everywhere else this
agreement applies.

## What `useActionCableReconnect` adds beyond ActionCable's own reconnect

The ActionCable (Rails' WebSocket framework) consumer already reconnects
automatically when the network comes back. `useActionCableReconnect`
(`app/frontend/hooks/useActionCableReconnect.ts`) adds one more thing:
when the browser regains connectivity, it triggers a partial Inertia
reload to refresh any score data that went stale while offline. This
keeps the UI accurate without interfering with ActionCable's own
automatic reconnect. Pages mount this hook themselves — it isn't wired up
centrally.

## Mobile: `useFocusedSync` on `BillDetailScreen` and `BillOfTheWeekScreen`

Both `BillDetailScreen` and `BillOfTheWeekScreen`
(`mobile/src/screens/BillDetailScreen.tsx`,
`mobile/src/screens/BillOfTheWeekScreen.tsx`) stay current the same way:
`useFocusedSync({ refresh, pollMs: 15000 })` polls every 15 seconds,
subscribes to the score websocket channel, and refetches when the network
comes back. All of that runs only while the screen has focus, so a screen
the user navigated away from stops polling — the mobile side of the same
15000ms agreement described above.

After a vote, `handleVoted` waits 1500ms and then refetches (the bill on
`BillDetailScreen`, the bootstrap data on `BillOfTheWeekScreen`). The timer
is cancelled if the screen goes away first.
