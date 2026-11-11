---
lat:
  mode: explanation
---
# The Notifications tab in the URL

The Notifications page remembers its open tab in the address as `?notifications_tab=<value>`, falling back to legacy `?tab=`, and switching tabs reaches no server. `NotificationsController#index` never reads the value.

## Which tabs there are

[[app/frontend/pages/Notifications.tsx#Notifications]] is the page `pageResolver.ts` picks ahead of the old V1 version it falls back to.

It has three tabs — `push` (the default), `sms`, `organizations` — and if the browser cannot do push notifications at all, the starting tab becomes `sms`, the only one the reader can act on.

`Notifications.tsx` is the page `pageResolver.ts` picks ahead of the old V1 version it falls back to. It has three tabs — `push` (the default), `sms`, `organizations` — and if the browser cannot do push notifications at all, the starting tab becomes `sms`, the only one the reader can act on.

## Why switching a tab reaches no server

All three panels render on every visit, so a tab click has nothing to fetch — but it used to make a request anyway, and removing it fixed two bugs at once, not one.

The request used to run a `router.visit` with `only: []`, meaning "fetch no props." An empty array cannot express that: Inertia decides a request is partial by testing whether `only` has any entries, so an empty one made the visit an ordinary navigation with no `X-Inertia-Partial-Data` header at all, and the server returned everything — measured at 8752 bytes of shared props plus a second 3602-byte round trip for the deferred `subscriptions` prop.

Removing the request also removed a duplicate one. Radix's `TabsTrigger` calls `onValueChange` twice for a single click — once from `onMouseDown` and again from `onFocus`, because activation is automatic by default. Radix normally swallows the second call by comparing against the current value, but the current value was read back out of the URL, and the URL was not rewritten until the server answered — so for the whole round trip the comparison still saw the old tab and let the second call through, and Rails processed both requests, the slower the server the wider the window.

The one thing the old request bought was an error toast if the visit failed, so an offline click did not look like a dead button — no longer needed, because there is nothing left to fail.

## Why the open tab is recomputed on every render instead of held in state

The page uses the shared `detectSupport` rather than a second copy of the same check, and works out the open tab from the URL on every render so the URL stays the only source of truth.

Copying the tab into `useState` instead would give the page a second source of truth that a server redirect could contradict — two controller actions redirect back with a tab in the address (`notifications_path(tab: ...)` after a save), so the page has to follow the address rather than its own memory. The one thing a `router.visit` used to provide for free is a re-render: rewriting the address in place tells React nothing, so `handleTabChange` dispatches a `useReducer` counter purely to make the component read the URL again — the counter itself is never read. `?notifications_tab=` (or legacy `?tab=`) is used when it is there; otherwise the page shows push, or sms if the browser cannot.

## What the in-place rewrite gives up

`history.replaceState` updates the browser's address but not Inertia's own record of the current page, which still holds the URL as it was when the page loaded.

So a reader who navigates away and returns with the back button gets the tab the page loaded with rather than the one they last clicked. Inertia offers no public way to rewrite its stored URL without making a request, and the trade is judged worth it: a settings page forgetting a tab across a back-button journey costs a click, where the old behavior cost a full prop payload twice on every single tab switch.
