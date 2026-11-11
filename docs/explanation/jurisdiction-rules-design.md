---
mode: explanation
summary: "Why SwayLocale::JurisdictionRules exists, why its rules split into two groups, and the history behind bill_chambers."
status: agent-extracted
related: []
---
<!-- vale Vale.Spelling = NO -->

# Why JurisdictionRules exists, and how it is organized

## The problem it replaced

Sway used to work out jurisdiction behavior by asking a locale which KIND it
was — is this Congress, is this a state — and everything that was neither
fell through to whatever Baltimore does.

That fallback is how a second city would have had its bills looked up in
Baltimore's Legistar: the vote service accepts any city, and the Legistar
client's own default jurisdiction is `"baltimore"`. A bill numbered 24-0123
in the new city would have collected the passage date of Baltimore's
24-0123, with nothing on screen to show it and no error anywhere.
`JurisdictionRules` closes that hole by making every locale declare its own
rules explicitly rather than falling through to a default.

## The two groups

The rules split into two groups, because getting one wrong is not the same
failure as getting the other wrong:

- **Where the data comes from** — `roster_source`, `vote_source`,
  `legistar_client`, `publishes_member_votes`. Getting one of these wrong
  reads somebody else's jurisdiction and believes the answer.
- **What the legislature is called** — `chamber_label`, `session_numbering`,
  `default_bill_chamber`. Getting one of these wrong only puts the wrong
  words on screen, so these degrade rather than refuse (see
  `SwayLocale#to_builder`).

## bill_chambers: replacing a guess with a declaration

`bill_chambers` lists every chamber a bill in a jurisdiction can belong to.
Before this field existed, two Bill Creator fields guessed at the same fact:
both asked whether the locale's city and region names differ — "is this a
city," spelled as a string comparison — and switched the chamber picker and
the senate vote date off when they did. The reasoning was right for
Baltimore and the test was not: any city added later would have had both
fields greyed out whether or not its legislature has two chambers, with
nothing on screen to say why. Asking what chambers the place *has* answers
it correctly for a city with a senate too.

The list is shipped as data, and nothing interprets it beyond membership
checks. Two reader methods used to — `picks_a_chamber?` and `has_senate?` —
with no caller on either side, while the Bill Creator read the list itself
directly. Both were deleted so the rule lives in one place.

`default_bill_chamber` exists for the same reason: the Bill Creator used to
start every non-Congress bill at `"council"`, so a Maryland bill opened as
a council bill in a state with no council.

## Why roster_refresher and open_states_jurisdiction are declared, not derived

`roster_refresher` is declared rather than derived from `roster_source`,
because a source name does not say which jurisdiction to fetch: two
OpenStates states need two different fetches, and `:curated` only says
Sway maintains the file, not that it is Baltimore's.

`open_states_jurisdiction` is this jurisdiction's own name in the
OpenStates API. OpenStates serves every state from one API keyed by this
name, so it is what keeps one state's people out of another's roster.
Without a name of its own, a locale reading OpenStates would take whatever
state the fetch happens to ask for — which used to be Maryland, hardcoded
into the refresher.

`legistar_client` is the jurisdiction's own segment of a Legistar address
(`/v1/<here>/...`), set only when `vote_source` is `:legistar`. Legistar
runs one instance per city, so this is the field that keeps one city's
matter numbers out of another city's bills.

`ROSTER_REFRESHERS` is declared as an explicit allowlist so a typo in a
declaration fails at boot rather than at 3am on a Sunday, inside a rescue.

## Why publishes_member_votes is a fact about the publisher, not the city

`publishes_member_votes` is true only when the jurisdiction says how each
member voted. Baltimore does not — none of the 200 matters checked carried
a roll-call — so its bills are scored on organization disagreement and
recency alone. This is a fact about the publisher, not about being a city,
so a city that does publish roll-calls declares true and gets the full
signal set.

## Why the initialize validations exist

`JurisdictionRules.new` raises `ArgumentError` on three mismatches, each
checked at declaration time so the two halves of a pair cannot drift apart
silently:

- `vote_source: :legistar` requires a `legistar_client`, and only
  `:legistar` may have one. A Legistar name on a locale that does not read
  Legistar is dead text; a locale that reads Legistar without one silently
  falls back to the client's default jurisdiction — the exact hole this
  class exists to close.
- A locale reading OpenStates (as either `roster_source` or `vote_source`)
  requires an `open_states_jurisdiction`, and only such a locale may have
  one — the same pairing problem one source along.
- `default_bill_chamber` must be one of `bill_chambers`. A default the
  jurisdiction cannot hold is the same defect one step along: the Creator
  would open every new bill in a chamber the place does not have.

`#legistar_client!` and `#open_states_jurisdiction!` refuse rather than
answer `nil` for the same reason: the declaration already guarantees a
locale reading that source names one, so reaching a `nil` here means a
caller asked for the wrong locale's client entirely.

## Why the declarations live in code, not the database

`JurisdictionRulesRegistry::DECLARATIONS` lives in code rather than in the
database, deliberately the same shape as `TermRulesRegistry`: nobody tunes
these from an admin screen, and a wrong value produces confident wrong
data rather than an error. Adding a locale means adding an entry here AND
in `TermRulesRegistry` — a spec holds the two lists to the same set of
locales, so neither can be added without the other.

## Congress's declaration: sourcing and session numbering

Congress's `JurisdictionRules` declaration draws its roster from
congress.gov and its history from `unitedstates/congress-legislators`;
both chambers publish every roll-call, so `publishes_member_votes` is
true.

`session_numbering: :congress_ordinal` counts from the 1st Congress, which
convened in 1789 and runs two years per Congress — the only locale
declared here that numbers its sessions this way; Maryland and Baltimore
both use `:term_years` instead.

## Baltimore's publishes_member_votes: what Sway does instead

Baltimore's `publishes_member_votes: false` means the city records only
whether a matter passed, never how each member voted — checked across 200
matters. Where the source has this gap, Sway guesses FOR from sponsorship
and marks those rows `inferred`; it does not pretend the vote was
unanimous.

Baltimore's `bill_chambers: %w[council]` is why the Bill Creator offers no
chamber to pick and no senate vote date to enter for Baltimore bills — it
has one council and nothing else. A city added later that has a senate
declares so and gets both fields.

## Why the Bill Creator still draws for an undeclared jurisdiction

The Bill Creator is a READ surface: for a locale nobody has declared in
`JurisdictionRulesRegistry`, it draws with no interesting score and no
badges, rather than an error page. Refusing belongs on the WRITE side
instead, and lives there — `BillInterestingScoreCalculator` will not
compute a score for a jurisdiction nobody has declared. A read failing
loudly for missing configuration would block an admin from even looking
at a bill while the declaration gap gets fixed; a write failing loudly
stops bad data from being produced in the meantime.

## Why the legislators-cache GCS upload path is named from the locale

`LegislatorsCache::BaseRefresh#upload_json_to_gcs` builds the canonical and
archive object paths from `sway_locale.name` rather than a hardcoded
string, for the same reason the rest of this doc describes: each refresher
used to name its own jurisdiction directly (`OpenStatesRefresh` was
`MarylandRefresh` and held its jurisdiction, its executives, and its path
all as constants). `sway_locale.name` is the whole
city-region-country name, not just the city, because two states can hold a
city of the same name — a hardcoded or partial name is exactly the kind of
value that reads one locale's roster and believes it is another's.

## The frontend type mirror (`app/frontend/index.d.ts`)

`default_bill_chamber`: Which chamber a new bill in this jurisdiction starts
in, before the admin picks. Null when nobody has declared this jurisdiction
(SwayLocale::JurisdictionRulesRegistry) — the Bill Creator then asks instead
of guessing. It used to guess "council" for every jurisdiction that was not
Congress, including Maryland, whose General Assembly has no council.

`bill_chambers`: Every chamber a bill in this jurisdiction can be in. Null
when nobody has declared this jurisdiction — the Bill Creator then leaves
the chamber picker and the senate vote date editable, because it has no
grounds to switch them off.

This replaces two fields that decided "is this a city" by comparing the
city name to the region name. The reasoning was right for Baltimore, which
has one council, and the test was not: any city added later had both
fields greyed out whether or not its legislature has two chambers.

## `useNewBillInitialValues`'s chamber default

The jurisdiction says which chamber a new bill starts in. This used to ask
whether the locale was Congress and default everything else to "council",
so a Maryland bill opened as a council bill in a state whose General
Assembly has no council.

Null when the jurisdiction is undeclared or absent: the admin then picks,
and `useBillFormSubmit`'s required-field check refuses to save until they
do — the same arrangement `legislator_id` uses. The label matches the
value because the chamber dropdown's own options are lowercase
(`components/bill/creator/inputs.ts`).
