---
mode: explanation
summary: "Why LegislatorsController#show is its own page, how its N+1-avoiding queries are shaped, and why the History payload uses a test-only forced-error mechanism"
status: agent-extracted
related: [docs/explanation/legislator-history-resource-design.md, docs/explanation/legislators-tab-switching-design.md]
---

# `LegislatorsController` design

## Why `#show` is its own page

`GET /legislators/:id` renders a page of its own for one legislator,
matching the mobile app's legislator detail screen. Re-rendering the list
page instead would omit `user_legislator_score`, which drives the charts,
Twitter handle, website link, and district.

## Why `set_legislator` preloads the active term

`LegislatorResource` asks for the active term and the district several
times while building `#show`. Loading the active term in `set_legislator`
(`Legislator.with_active_term.find`) lets those lookups reuse it, instead
of each one scanning every term in the database.

## Why `waiting_for_new_term?` exists

It distinguishes two causes of an empty list, since they call for opposite
actions: either Sway has never worked out who represents this person (try
searching again), or every term it knows about has ended and the new
roster isn't seeded yet (searching again can't help — the page says so
instead of offering a dead-end button). Congress hits the second case
every two years on 3 January.

## Why the frontend `legislator` route helper accepts two argument shapes

`app/frontend/sway_constants/routes.ts`'s `legislator` helper:
`config/routes.rb` declares only `resources :legislators, only: [index,
show]`, so the one path that exists is `/legislators/:id`. An earlier
helper built `/legislators/:localeName/:external_id`, which matches no
route: it redirected to production, and the browser then blocked the
result as a cross-origin request. The old `BillComponent` still calls
this with `(localeName, id)`, so when a second argument is given it is
treated as the id — either way the result is `/legislators/:id`.

### The frontend copy for this state (`PARITY_COPY.legislators.waitingForNewTerm`)

Shown instead of `noneFound` when Sway DOES know who represented this
person and every one of those terms has finished. The seats turned over
and nobody has been recorded in the new ones yet, so searching again
cannot help and the button is hidden. Congress reaches this every two
years on 3 January.

## Why `json_legislators` is memoized

It is held for the request, because `#waiting_for_new_term?` asks the same
question and this walks every term and score row the reader can see.

## Why `build_json_legislators` is shaped this way

Scoped to the locale the user is viewing, using the `sway_locale_id` column
on legislators directly (no join through districts), so legislators from
the user's other registered locales don't leak in. Joining to
`active_term` does double duty: only currently-serving legislators reach
this list, and `history_payload` covers everyone else. The preloads put
title, district, and lifetime totals in memory instead of costing one
query per legislator.

## Why `legislator_with_score` doesn't require `active: true`

It builds the JSON for one legislator on `#show`, merging the same pieces
`#json_legislators` does so the detail page matches a list row's shape —
including for someone no longer in office (`LegislatorResource` fills their
title/district from their most recent term).

It deliberately does NOT require `active: true`: a former representative's
detail page is reached from a switched-off History entry. Only one
user/legislator link can exist, so this still finds at most one;
`#current_term_score_for` handles scoring for a switched-off link.

## Why `Legislator.tsx` shows the "Representatives" back link only to signed-in users

Anyone can view a single legislator — a visitor who is not signed in can land
there from the sponsor of a public bill — but `/legislators`, the list page,
needs an account. So `Legislator.tsx` shows the "Representatives" back link
only to signed-in users; otherwise a visitor's own breadcrumb would throw
them at the login screen.

## Why `Legislator.tsx` treats `active === false` as its own case

A former representative has no active term, so `LegislatorResource#active`
(`Legislator#serving?`) is false. `legislator_with_score` also finds scores
through a DEACTIVATED user_legislator link (see above), so the "current"
scope already carries a former representative's frozen most-recent-term
score. Nothing on `Legislator.tsx` has to fill in a substitute.

## Why `Legislator.tsx`'s district label checks `typeof === "number"`

`IDistrict#number` is declared as a number, but that does not always hold
once the code runs — a legislator's district can arrive with `number`
missing altogether. A `!== null` check does not catch `undefined`, which
puts the words "District undefined" on the page. `typeof === "number"`
catches both null and undefined without tripping the `eqeqeq` lint rule.

## What `Legislator.test.tsx` pins about the tab wording

Pins the EXACT agreed wording. For someone still in office, the first tab
reads "Current term" and the term's years sit under the tabs as supporting
text ("2025–2027", joined by an en dash). For a former representative, the
first tab is RENAMED to that term's years ("2019–2021") and an "Ended" stamp
appears next to the name. The years come from `LegislatorResource`'s display
term.

## Why `LegislatorsLocaleGuard.test.tsx` is its own file

The Representatives text read `locale.name` without checking it first, even
though `locale` can be missing and is read as `locale?.id` everywhere else —
so with no locale set the page crashed. This file covers rendering when
there is no locale. The sibling `Legislators.test.tsx` deliberately supplies
a real locale for its poll checks, so the crash needs its own file with a
different `useLocale` stand-in.

## Why `legislator_score_payload` always attaches both numbers

It always attaches both `user_legislator_score` for the current term, and
`lifetime_score` across every term, added up while the request is being
served rather than cached anywhere. Both `#json_legislators` and
`#legislator_with_score` call this, so a list row and the detail page can
never disagree.

## Why `current_term_score_for` picks the row it does

If the link is active and the legislator is serving, it uses exactly that
term's row — the current tab must never show a leftover tally from an
earlier term. If the link has been switched off, it uses the most recent
term the user has a frozen row for, matching what the History payload
picks.

`.to_a` reuses score rows the list path already loaded at no extra query
cost; on the single-legislator path, where nothing is preloaded, it costs
one query.

## `history_payload` and `history_prop`

The History payload is built only when it is asked for. A signed-out
visitor gets no sessions, since `#show` is reachable without signing in.
It is limited to the locale being viewed, the same as `json_legislators`.

`InertiaRails.optional` keeps it out of a full page load, and the browser
asks for it via `router.reload({ only: ["history"] })` when the History tab
opens. It is left out of the polling list on purpose — past sessions cannot
go stale.

When the request already says the History tab is open (`?tab=history`),
`history_prop` sends the payload right away instead of waiting to be
asked — see
[Why Legislators.tsx switches tabs without a server round trip](legislators-tab-switching-design.md)
for why the frontend copies the open tab into the URL this way, and why an
ordinary Inertia visit (as opposed to a partial reload) otherwise leaves
optional props out.

### The test-only forced-error branch

The `forced_history_error_attempt` branch is test-only. It replaces the
`history` key with a top-level `errors` prop, since `router.reload`'s
`onError` only fires when the response carries a filled-in `errors` prop —
a raw exception or plain HTTP failure opens Inertia's own error dialog
instead. `errors` and `history` can't both be present: the client's
"failed and no history" check requires `history` to be genuinely missing
from the response, not just alongside a resolved error.

`forced_history_error_attempt` itself is test-only, like the analogous
branches in `Test::SessionsController` and
`Organizations::MembershipInvitesController`. It returns which attempt this
is (counting from 1), or nil when not forcing a failure. It fails EVERY
history reload while the test param is present, not just the first, so
`spec/system/legislator_history_spec.rb` can prove the retry button sends a
fresh request by counting requests rather than racing Inertia's own
handling on a busy CI machine.

It only counts an attempt when the request really is the History reload —
a full page load never asks for `history` at all, and would otherwise burn
attempt 1 before anyone opened the History tab.

## Browser coverage for the list-to-detail navigation

`ROUTES.legislator` was fixed to build the one-segment path
`/legislators/:id`. Before that fix, clicking "View representative" built a
two-segment path that led nowhere: the browser was redirected to a
different origin and the request died on a cross-origin check.
`spec/system/legislator_detail_spec.rb` jumps straight to the detail page,
so the trip that was actually broken — list, card link, detail page — had
no browser coverage until `spec/system/legislators_navigation_spec.rb` was
written to click the real link.

## Testing the retry button with an XMLHttpRequest#open counter

`spec/system/legislator_history_spec.rb`'s error-state-and-retry example
 shipped with only a component-logic check and a type check before
this browser test. `?_test_force_history_error=1` makes
`forced_history_error_attempt` fail on purpose, and works in the test
environment only; while the parameter is in the URL every history fetch
fails the same way, so the error UI is still on screen after a retry.

What proves the retry button actually SENT a new request, instead of
re-drawing what was already there, is a counter: a small test-only wrapper
around `XMLHttpRequest#open` that counts requests as they START. It
deliberately does not read response bodies — those lined up unreliably
with any one request when the machine was busy, while `open()` firing is a
dependable signal that does not depend on timing.

## Browser coverage for the detail page

`spec/system/legislator_detail_spec.rb` covers `/legislators/:id`, which
had no browser coverage before and is also where the bug lived
(above). The voter-agreement charts panel
(`data-testid="legislator-detail-charts"`) renders only when the signed-in
user has a score for that legislator, and each contact row — email,
phone, Twitter — carries its own test id.

Its legislator fixture is given a current `legislator_term` explicitly:
title, district, and "still serving?" all come from a legislator's term,
and a legislator with no term has no active term, so `LegislatorResource`
leaves out `user_legislator_score` entirely and the charts panel never
renders — the same fix the shared fixtures in `spec/support/setup.rb` got.
