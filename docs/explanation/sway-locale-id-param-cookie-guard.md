---
mode: explanation
summary: "Why ?sway_locale_id= is validated before being written to the permanent cookie, and why the write path and the read path answer an unknown id differently."
status: agent-extracted
related: []
---
<!-- vale Vale.Spelling = NO -->

# Why the sway_locale_id param is validated before it reaches the cookie

## The bug

`?sway_locale_id=N` used to be written into `cookies.permanent` without
anyone asking whether a jurisdiction by that id existed. A bookmarked
link with a stale id — or a locale deleted while somebody was reading —
therefore poisoned a cookie that lasts twenty years, and every later
request fell through to the default. A Baltimore reader saw Congress
bills, on every page, with nothing on screen saying so, until they
happened to pick a jurisdiction again.

## Why the write and the read are tested, and answer, differently

Writing the reader's jurisdiction is a **write**, so an id naming
nothing is refused outright — nothing gets written to the cookie.
Drawing the page is a **read**, so it still renders — with whichever
jurisdiction is really in effect, and a flash message saying which one
that is and why. The two halves are tested separately in
`spec/requests/sway_locale_id_param_spec.rb` because they answer
differently on purpose.

## Why the resolved id is memoized

`ApplicationController#requested_sway_locale` memoizes the jurisdiction the
address asked for (or `nil`, when it named none or named one that does not
exist). Both the `set_sway_locale_id_in_session` `before_action` and
`#find_current_sway_locale` need the answer, and asking twice would cost a
second query on every request that carries the parameter — which, for a
mobile client, is every request it makes.

## Why the explicit query param wins on read

`#find_current_sway_locale` checks `requested_sway_locale` (the
`?sway_locale_id=N` query param) before the cookie. Mobile
clients authenticate with bearer tokens and carry no cookies, so their
`apiClient` adds `?sway_locale_id=N` to every request as the mobile
stand-in for the web's locale cookie.

## Why `SwayLocalesController#show` never writes the cookie either

`GET /sway_locales/:id` is a read, and a GET must not change anything
that sticks around — so this endpoint does not set the
`sway_locale_id` cookie as a side effect, even though it returns exactly
the locale a write path might otherwise remember. The active locale is
still remembered through the ordinary `?sway_locale_id=` query-param
path, which `set_sway_locale_id_in_session` picks up during normal
navigation; this endpoint just never becomes a second, hidden way to set
it.

## Why the read path also deletes a dead cookie

A `sway_locale_id` cookie naming a jurisdiction that no longer exists is
dead weight that answers nothing on every request for the next twenty
years. `#find_current_sway_locale` deletes it outright rather than merely
falling through to the default: browsers poisoned before the write-side
guard above existed are the reason this is a delete and not just a
fallback — without it, their readers would stay on the default locale until
they happened to pick a jurisdiction again, with nothing prompting them to.

## Mobile: `BillOfTheWeekScreen`'s locale picker

Picking a locale in `BillOfTheWeekScreen`
(`mobile/src/screens/BillOfTheWeekScreen.tsx`) really does switch locale.
`refetch(id)` saves the choice in the prefs cache, tells `apiClient` to
attach `?sway_locale_id=N` to every later request, and refetches the
bootstrap data; the server reads that parameter to decide which locale to
serve. The web does the same thing with a long-lived `sway_locale_id`
cookie.
