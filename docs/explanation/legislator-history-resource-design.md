---
mode: explanation
summary: "Why LegislatorHistoryResource scopes and groups the way it does, and the N+1 traps its query shape avoids."
status: agent-extracted
related: [legislators-tab-switching-design]
---

<!-- vale Vale.Spelling = NO -->

# Why `LegislatorHistoryResource` is shaped the way it is

`LegislatorHistoryResource` returns "legislators you used to have": sessions
(newest first), each with the user's ended legislator links in the given
locale.

Scoping by locale matches `json_legislators`, so every tab shows the same
active locale. Grouping into sessions happens only in this resource, so web
and mobile get the identical shape instead of each re-deriving it.

## Why `active_district_ids` is loaded once, up front

`active_district_ids` used to be loaded inside `ended_reason`, which fired
the same query again for every single entry. Loading it once before the
loop turns that into a single query regardless of how many ended legislator
links a user has.

## Why the locale filter goes through the legislator's own column

`sessions_for` narrows by the legislator's own `sway_locale_id` column.
Never reach the locale through the district instead — that path INNER
JOINs by way of the legislator's current term.

## Why the portrait's attachment and blob are eager-loaded

The portrait comes back through the copy `LegislatorHistoryResource` holds,
which reads an attachment row and then a blob row — two more queries per
past representative without eager-loading them. This list is the one place
that query count keeps growing as a user accumulates history.

## Why `ended_reason` needs no query per entry

`ended_reason` tells "the term ended" apart from "the user moved districts"
by checking the term's district against the user's current districts.
`user_districts` rows are never deleted, only flagged inactive, so this only
needs the active set the caller already loaded once — no query per entry.

## Why `session_label` falls back to years-only instead of guessing

The session label comes from the locale's own declared rules
(`declared_jurisdiction_rules`), not from guessing the locale's kind. A
locale with no declared rules gets years only, no chamber name — a wrong
body name would mislead more than an absent one.

## Why spec/system/legislator_history_spec.rb names its locale explicitly

The example asserting the "City Council" heading depends on
`session_label` asking the locale for its own rules — a city jurisdiction
produces "City Council," while Congress numbers its sessions instead
("118th Congress"). The factory no longer invents a city; it rotates
through the three jurisdictions Sway really seeds, so an unnamed locale
made this example depend on how many locales the process had already
created, and it could as easily draw Congress. A spec about a particular
jurisdiction has to build that jurisdiction by name
(`create(:sway_locale, city: "baltimore", ...)`) rather than taking
whatever the factory hands out.

## The frontend type mirror (`app/frontend/index.d.ts`)

The History payload, already grouped by the server:
`LegislatorHistoryResource.new(user).serializable_hash` returns
`{ sessions: [{ session_label, entries: [...] }] }`. It is sent lazily
(`InertiaRails.optional`), the first prop in the codebase to work that
way, which means `history` is completely ABSENT from `IProps` until the
first `router.reload({ only: ["history"] })` asks for it. That is why the
page props below declare `history?` instead of requiring the key.
