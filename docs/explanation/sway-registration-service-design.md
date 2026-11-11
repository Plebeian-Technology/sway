---
mode: explanation
summary: "Explains SwayRegistrationService's district_legislators resolver, the current-occupants-only successor filter, and why create_invite swallows a validation failure rather than aborting registration."
status: agent-extracted
related: [env-secret-blank-value-handling.md]
---
<!-- vale Vale.Spelling = NO -->

# Why SwayRegistrationService is built the way it is

## Why create_user_legislators also writes a UserDistrict row

Alongside the user-to-legislator link, `#create_user_legislators` saves the
plain fact that this user lives in `l`'s district, so it can be compared
later. Rows are never deleted: if the user moves back, `active` is
switched on again, the same way `UserLegislator` works. `l.district` could
only be nil if `l` lost its active term between `district_legislators`
finding it and this line, which cannot happen inside one straight-through
call — the check is belt-and-braces, not something the code relies on.

## Why the method returns the created records, not a boolean

Project convention: service objects return the created ActiveRecord
instances, not the boolean result of `ul.save!`. Returning the persisted
`UserLegislator` lets callers use the records directly.

## Why district_legislators is public

`#district_legislators` is the current-term legislators this address
resolves to. It is public (it used to be private) because
`ReconcileUserDistrictsService` reuses it verbatim, so reconciliation never
grows a second address-to-legislator resolver. It stays side-effect-free
(no writes), so calling it outside `#call`/`#create_user_legislators` is
safe.

## Why current_occupants_only exists

Whether a legislator counts as serving (`Legislator.serving?` /
`LegislatorTerm.current`) is derived from the dates on that legislator's
OWN term. So a legislator who resigned mid-term, with no newer term of
their own, satisfies "current" forever — nothing ever supersedes their
single term. Once a successor is seeded for the SAME district, both the
departed legislator and the successor pass the filter at the same time,
silently doubling the district's "current" occupant instead of the
departed one disappearing. This fixes the "stranded on a former rep" gap:
it keeps only the legislator(s) whose active term has the LATEST
`term_start_year` among candidates sharing a district. Ties all
survive — Maryland's multi-seat districts co-elect several Delegates
sharing one `term_start_year` — while a strictly later successor drops the
earlier occupant.

## Why the OpenStates API key is read once and reused

`#find_legislators_from_open_states_geo_endpoint` reads the key once and
reuses it, so the value that passes the blank-check is provably the same
value sent as the `apikey` param. A guard and a use that each read the
`ENV` separately can disagree — the exact bug once found in
`ClaudeAdapter#api_key`. See
[env-secret-blank-value-handling.md](env-secret-blank-value-handling.md).

## Why the OpenStates request goes through Sway::FaradayStack

Getting legislators from OpenStates goes through `Sway::FaradayStack`
(bounded retries plus a timeout), passes `apikey`/`lat`/`lng` as request
params, and turns a non-2xx response into the designed
`SwayGeocode::ServiceUnavailableError` — instead of letting `nil.filter`
raise a `NoMethodError` that escaped the rescue below.

## Why the results array is built with Array(...)

`Array(...)` turns a body with no `"results"` key into the "no legislators
found" path instead of raising on nil. `JSON.parse` returns untyped
dynamic data (OpenStates person records), so the element type is honestly
untyped.

## Why create_invite swallows a validation failure

`create_or_find_by!` resolves a create-vs-find race on the
`(inviter_id, invitee_id)` unique index instead of raising
`RecordNotUnique`. Invite bookkeeping must never abort a registration — a
missed `Invite` row is far cheaper than a rolled-back registration — so a
genuine validation failure is logged and swallowed rather than raised.
