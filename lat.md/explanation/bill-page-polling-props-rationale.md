---
lat:
  mode: explanation
---

# Why Bill.tsx and BillOfTheMonth.tsx poll the props they do

Both pages pass a `POLLING_PROPS` list to `usePoll`, `useScoreSubscription`, and `useActionCableReconnect`, which all call `router.reload({ only: POLLING_PROPS })`.

The web and mobile apps have a written agreement to keep the poll interval at 15000ms — do not change it on one page without changing it everywhere.

## Bill.tsx

`POLLING_PROPS` is `["bill_score", "organizations", "user_legislator_emails"]`.

`organizations` (the stances organizations take on this bill) is drawn on this page but used to have no live update and no poll, so a newly approved stance never showed up unless the reader reloaded. Adding it to the list the score sync already uses gives it the same 15-second poll and the same WebSocket path.

`user_legislator_emails` is on the list too, so the compose dialog's status moves from pending to sending to sent on its own, with no reload.

`billPollingTuple.test.ts` is a tripwire against drift: the `POLLING_PROPS` list on the Bill and Bill of the Month pages must keep `organizations`, so an organization's stance on a bill updates by itself on the same rhythm as the scores. The other half of the deal — the server actually sending `organizations` on a partial reload — is checked in `spec/requests/partial_reload_contracts_spec.rb`.

## BillOfTheMonth.tsx

`POLLING_PROPS` is `["bill", "sponsor", "organizations", "user_vote", "bill_score"]`.

`organizations` (drawn by `BillContent`) travels with the score sync, so a newly approved stance appears without the reader reloading — same rationale as `Bill.tsx`.

`bill`, `sponsor`, and `user_vote` are on the list as well. Unlike `/bills/:id`, which bill this page is about is chosen and scheduled by an admin, so it can change under a reader who is just sitting there. Leaving `bill` off caused two problems:

- A locale with nothing featured drew the empty state and then never asked
  for a bill again, so a reader waiting for the admin to publish one had no
  way forward but a manual refresh — never an acceptable step in a workflow
  here.
- When the admin pointed the page at a different bill mid-session, the bill
  swapped while the sponsor, the reader's own vote, and the organization
  stances beside it still described the old one.

Everything this page draws follows from that single choice of bill, so it all refreshes together. `Organization.tsx` works the same way and names its whole set for the same reason.

## Legislators.tsx

`Legislators.test.tsx` pins the 15-second `usePoll` fallback and the list of props `useScoreSubscription` refreshes on the Legislators page.

The written agreement above keeps the web and mobile apps refreshing at the same rate: `usePoll(15000, { only: ["legislators"] }, { background: "pause" })` with `useScoreSubscription` watching the SAME list. Those tests hold those values in place — do not change `15000` or the list without changing it everywhere else this agreement applies.

## Why user-facing polling pauses on background tabs

Passing `{ background: 'pause' }` halts the 15-second polling interval whenever a browser tab is hidden, avoiding origin load when nobody is watching.

By default, Inertia's `usePoll` continues background requests at a throttled cadence. In Sway, user-facing pages (`Bill.tsx`, `BillOfTheMonth.tsx`, `Legislators.tsx`, `Legislator.tsx`, `Organization.tsx`, `Organizations.tsx`, and `Influence.tsx`) provide real-time updates via ActionCable push events. Because `useActionCableReconnect` and `useScoreSubscription` already reload stale props when connectivity returns, running background tab polls wastes server CPU and database bandwidth. Supplying `{ background: 'pause' }` suspends queries immediately while hidden and resumes promptly upon returning to the tab.

## What useActionCableReconnect adds beyond ActionCable's own reconnect

The ActionCable (Rails' WebSocket framework) consumer already reconnects automatically when the network comes back.

`useActionCableReconnect` (`app/frontend/hooks/useActionCableReconnect.ts`) adds one more thing: when the browser regains connectivity, it triggers a partial Inertia reload to refresh any score data that went stale while offline. This keeps the UI accurate without interfering with ActionCable's own automatic reconnect. Pages mount this hook themselves — it isn't wired up centrally.

## Mobile: useFocusedSync on BillDetailScreen and BillOfTheMonthScreen

Both `BillDetailScreen` and `BillOfTheMonthScreen` (`mobile/src/screens/BillDetailScreen.tsx`, `mobile/src/screens/BillOfTheMonthScreen.tsx`) stay current the same way.

`useFocusedSync({ refresh, pollMs: 15000 })` polls every 15 seconds, subscribes to the score websocket channel, and refetches when the network comes back. All of that runs only while the screen has focus, so a screen the user navigated away from stops polling — the mobile side of the same 15000ms agreement described above.

`BillOfTheMonthScreen` has two data sources, so it calls `useFocusedSync` twice, each call with its own refresh and its own timer, score subscription and network listener: the screen shell reloads bootstrap, which carries the featured bill's own fields, and the body keyed by the featured bill reloads the bill detail, which carries the sponsor, scores, district tallies, positions, news and constituent-letter counts. One call could not serve both, because the detail hooks live in the body and exist only once there is a featured bill ([[mobile-bill-surface-components-design#BillScreenTabs#Why the featured screen fetches the bill detail too]]).

After a vote, `handleVoted` waits 1500ms and then refetches: the bill on `BillDetailScreen`, and bootstrap and the bill detail on `BillOfTheMonthScreen`, so the reader's vote and the scores it moved are fresh in both. The timer is cancelled if the screen goes away first.
