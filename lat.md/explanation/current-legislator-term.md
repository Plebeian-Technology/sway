---
lat:
  mode: explanation
---

# Which term a legislator is serving now

Sway holds no column saying a legislator is currently in office. Whether a term is running is derived from dates every time it is asked, by `LegislatorTerm`'s `current` scope, so a term that has quietly ended cannot go on counting.

The scope carries no flag and no `finalized_at`. For each legislator, the date
bounds keep the one term running today: begun on or before the target date, and
not yet ended. Because each legislator serves consecutive, non-overlapping term
windows, the date interval in SQL resolves the active term without requiring
Ruby grouping, whether evaluated across all legislators or narrowed to a single
person.

The end of the window matters as much as the start. An earlier version asked
`TermWindow.covering`, which checks only that a term has begun, and the
consequence was that departed members kept appearing on the legislators page
and kept being re-scored on every vote. `TermWindow.running_on` checks both
ends. It returns `nil` when no term covers the date, which is a real
answer — the person held no office that day — rather than an error.

This locale-branching date arithmetic lives in one place on purpose. A second
implementation elsewhere would be a second opinion about who holds office.

## A locale with no declared calendar is skipped, not refused

The scope reads terms across every legislator, so raising for one locale with no
declared term rules would take the legislators page down for all three at once.

Undeclared locales already exist in production, because registering a user
creates a locale row for their own city and state. With no declared calendar
Sway cannot say when such a term ran, and so cannot claim the person holds
office; skipping is the honest answer rather than a workaround. In SQL,
undeclared locales evaluate to `NULL` in the `TermWindow.convening_date_sql`
`CASE` statement, safely excluding them from matching any date range.

## Why the candidates are bounded in SQL first

`TermWindow` convening-date math is pushed directly into SQL clauses so rows are bounded and evaluated entirely in the database engine before becoming Ruby objects.

`LegislatorTerm.current` pushes convening-date calculations into SQL (`TermWindow.begins_on_sql` and `TermWindow.ends_on_sql`), so candidate rows are filtered before they become Ruby objects. For Congress, SQLite uses `printf('%04d-01-03', year)`. For Maryland, it evaluates `date(printf('%04d-01-01', year), 'weekday 3', '+7 days')`. For Baltimore, it evaluates `date(printf('%04d-12-01', year), 'weekday 1', '+3 days')`.

Undeclared locales safely evaluate to `NULL` in the `CASE` statement, which filters them out without errors. The association's owner scope and roster preload are described in [[current-legislator-term#Active-term association and roster preloading]].

## Active-term association and roster preloading

The active-term association uses a qualified scope, while collection readers opt into the district and locale preload they serialize.

[[app/models/legislator.rb#Legislator]] declares `active_term` with the
qualified `LegislatorTerm.current` scope. The qualified form lets the RBS type
checker resolve the association's scope; an unqualified `current` call emits
the same runtime SQL but is not resolved by Steep. At runtime, the term's SQL
date interval and the association's legislator ID constrain the same query,
before term rows are materialized.

`with_active_term` is an explicit collection preload, not a default scope. It
includes `district: :sway_locale` through the current-term-backed district
association, covering the term title, district, and locale reads in a roster.
The preload follows the association consumers use: a nested preload under
`active_term` does not substitute for the `district` preload when the reader
accesses `Legislator#district`.

## Why the answer is worked out once per request

`LegislatorTerm.current` evaluates convening date boundaries directly in SQL, while `current_ids` memoizes `unscoped.current(today).pluck(:id)` on `Current` at most once per request for callers needing the global identifier set.

For operations that require the complete list of active term IDs across all legislators, `LegislatorTerm.current_ids` provides a convenience entry point. Rather than filtering candidate models in Ruby, `current_ids` executes `unscoped.current(today).pluck(:id)` in SQLite. Because plucking the entire table's active IDs is an unscoped database query, `current_ids` caches the resulting identifier array on `Current.current_legislator_term_ids` for the lifetime of the request.

Nothing in the plucked answer can change during a request unless term data is written. The memo is keyed on today's date so requests spanning UTC midnight recompute rather than serving yesterday's identifiers. When any write statement touches `legislator_terms`, the cache is cleared immediately.

`Current` is chosen over a class variable because Rails resets it automatically around every request and Solid Queue job. It is not `Rails.cache`: the identifier set is request-scoped, eliminating cache invalidation complexity across external processes while keeping full-roster ID queries cheap.

## Why the memo is dropped by watching statements, not callbacks

An `after_commit` on the model is the obvious way to invalidate the memo and it
is not enough here. It only sees writes that go through a record's own
lifecycle, and the writes that matter most do not.

Direct term mutations such as `SeedLegislatorTerms` use `update_columns`, which
fires no callbacks at all, and then ask whether the person is still serving — so a
callback-based memo would answer yes about somebody whose term was just modified.
`update_all` and `delete_all` on a relation are the same story, and both are
used throughout the data migrations and the term seeder. (Historically,
`RetireDepartedLegislatorsService` also used `update_columns` before missing-name
date mutation was disabled.) This is not a hypothetical: it is what five specs
reported the first time this memo was written against `after_commit`.

So the memo is dropped by an initializer subscribed to `sql.active_record`,
which watches for an `INSERT`, `UPDATE`, `DELETE` or `REPLACE` naming
`legislator_terms`. That is one place, and it sees every write ActiveRecord
issues regardless of which API produced it. The substring test runs before the
pattern match so the overwhelming majority of statements — the ones that never
mention the table — cost a single `String#include?`.

Invalidating on a write that later rolls back only means recomputing an answer
that had not changed, which is the direction an error here should fall.

## Why narrowing by legislator has its own entry point

`current_for` scopes term resolution to specific legislator identifiers by composing `where(legislator_id: legislator_ids).current` directly in SQL, avoiding full table scans.

`LegislatorTerm.current_for(legislator_ids)` constructs an ActiveRecord relation combining the `legislator_id` restriction with the SQL convening-date expressions from `TermWindow`.

Under the previous Ruby-based architecture, `current_for` loaded candidate term rows for the requested legislators into memory and evaluated them using `TermWindow.running_on` to bypass the global candidate scan. With convening dates pushed to SQLite, `current_for` executes entirely in SQL. The database uses `index_legislator_terms_on_legislator_id_and_term_start_year` to evaluate only candidate terms for the specified legislators.

Because `current_for` returns an ActiveRecord relation, operations like `.pluck(:legislator_id)` or `.exists?(...)` execute purely in the database without allocating `LegislatorTerm` model instances in Ruby memory. Retaining `current_for` provides an explicit, self-documenting method for querying terms across a subset of legislators — such as a voter's assigned representatives — without loading unneeded records.

## Which term a payload describes

A serialized legislator describes one term: the one running today when there is one, and the most recent otherwise. `LegislatorResource#display_term` picks it, and the title, the term years, the term dates and the district all read from it.

`active` is the exception, and deliberately: it answers whether a term is running
today, so a former member arrives with a district and a title and `active` false,
rather than with everything blank.

The district reads through the association's `source:` option rather than through
a block. Alba drops an association's block whenever `resource:` is given —
`Association#initialize` returns before it assigns one — so the block that was
written here served no purpose and the district silently came from
`Legislator#district`, which is a `has_one through: :active_term` and therefore
nil for anybody no longer serving. `source:` is honoured alongside
`resource:`, and it is `instance_exec`'d against the legislator, which is why it
calls the class-level `display_term` rather than the private instance method the
attribute blocks use.

## The vote-entry roster is everyone who ever held the seat

The Bill Creator's vote-entry list carries every legislator with any term in the locale, each one marked with whether a term is running today, rather than only the people serving now.

A bill's votes belong to the day it was voted on, and the seats on that day are
not always the seats today. A roster filtered to today's office-holders left an
operator no way to enter or correct a departed member's vote on a historical
bill, which is the manual repair path when a re-fetched roll call drops a
departed member's vote.

Each row is serialized by `LegislatorResource`, whose `display_term` falls back
to a legislator's most recent term when no term is running, so a departed member
still arrives with a district and a title rather than with both blank. The
`active` field carries the serving answer, and the vote-entry row labels the
people it is false for.

Nominations stay Senate-only. A `PN` bill in Congress drops anyone whose
displayed term is a House title, which is the same rule as before applied to the
term being shown instead of only to a running one.

### The displayed term needs its own district preload

The Bill Creator query uses `[[app/models/legislator.rb#Legislator#with_term_history]]` so `active_term` and `legislator_terms` both preload their nested district, locale, seat, and score rows.

The serializer reads `active_term` first for displayed term fields and iterates `legislator_terms` for term history, so both associations require their nested preloads to prevent per-person and per-term queries. This changes query cost without changing the roster, its nomination exclusions or its serialized keys. Coverage needs a growing roster with distinct districts to expose linear query growth, plus the historical fallback. Any later shared prop-builder extraction carries this preload with the roster reader.

### Matching a name resolves against the roster of the vote's own day

A fetched vote sheet names people, and those names are matched against whoever
held a seat in that jurisdiction on the day the chamber voted.

Matching against today's roster loses every vote cast by somebody who has since
left: on one measured bill, 53 of 405 published votes went missing, silently,
which is the failure mode that makes this worth stating. Where no day was
recorded there is nothing to resolve against but today, and that fallback is
logged rather than taken quietly.

A title separates a senator from a representative sharing a surname. It cannot
separate two senators of the same surname, and a seat that changed hands
mid-term leaves both of its holders reading as running, so an unresolvable name
records nobody rather than a guess.

`GenericLegislatorVoteUpdateService` applies this historical roster resolution when persisting normalized votes. It constructs a `LegislatorRoster` on the vote's date (`voted_on`, mapped to local calendar days according to jurisdiction timezone rules) to resolve voter identifiers and senators by name and state before falling back to direct database ID matching. Where configured by `enable_historical_fallback`, unmatched voter identifiers trigger a single retry via `HistoricalElectedOfficialImporter` before unresolvable tokens are reported alongside matched counts as [[legislator-vote-upserter-guard-rules#What each upsert outcome means for vote coverage|vote coverage]].

## A date before every term this person served has no term

A date earlier than anybody's first term answers with nothing rather than with the nearest term, and every caller already treats that nothing as "leave this bill out".

The alternative shipped once and was worse than an error. Asked about a day
before somebody took office, the lookup handed back their earliest term, which
pulled a bill decided before they arrived inside their first term and scored
them on it. "Outside every term" therefore has to mean "they were not there
yet" as well as "they had already left", and a score for such a bill counts
toward none of that person's terms.

## A term carries the day it really began

A term is stored as two years, so on its own it starts on the locale's handover day whether or not the person was there. A published start date recorded on the term overrides that.

Without one, a mid-cycle successor reads as seated from the January handover,
and a roll-call line naming a surname and a state then matches two people
equally well — the case where two senators from the same state share a surname
and neither can be identified. `began_on` is the mirror of `ended_on` at the
other end of the term, and it is recorded only where it is worth trusting: the
day Sway first observed somebody in a seat is written down when the seat, the
source and the person's absence from earlier fetches all agree, and each of
those three rules out a different way of being wrong.

## A scheduled end whose day has passed is not yet a departure

A departure date published ahead of time does not become real just because the day arrives, so a scheduled end stays unwritten while the roster still lists the person.

An appointee may have won the special election that was supposed to replace
them, and upstream corrects the date only afterwards. The seeder leaves an
incoming scheduled end unwritten while the list of elected officials still
names the person. Stored departure dates and their sources are preserved
byte-for-byte; reappearance with service history never clears a stored departure
date. Modifying or removing an established departure date requires the planned
manual repair process.

## Why a Congress term is rebuilt from published history

congress.gov reports one entry per Congress, so a senator's six-year term arrives as three two-year pieces with nothing saying which of them was one seat.

`LegislatorsCache::CongressTermHistory` reads the published term history
instead, which carries the real start and end of each term. Sway still records
a term as two years and turns every seat over on the same January date, so what
the history decides is which way each real term is rounded, and a record whose
dates cannot be read produces no answer at all rather than the subset that
happened to parse. A complete history can correct or retire stored terms; an
unreadable history cannot authorize a partial correction or deletion.

### A later term does not rewrite an earlier row

A new source start year gets its own term row, leaving the prior term and its score rows attached.

Complete published history may still correct fields on that earlier row when it publishes a changed value for the same start year.

### A term keeps its assigned district and seat

Each term keeps the district and seat assigned to that period of service. A legislator's later district does not move an earlier term, and correcting a term from published history does not replace its seat assignment.

### An open roster stretch uses the current calendar window

An open current roster stretch derives its running term from the locale calendar.

For Congress, the preparer uses the latest source term and derives the running window from the locale calendar. That window can roll forward as new cycles convene; it is calendar-derived rather than an exact published interval.

## Departed members are put back before term history is asked

congress.gov lists only current members, so somebody who leaves simply drops out of the fetch and is never looked at again.

The term they were left with — running to 2027, say — could then never be
corrected, because nothing in the roster mentions them any more.
`LegislatorsCache::DepartedMemberEntries` rebuilds an entry for each of those
people out of what Sway already holds, so the term-history step has somebody to
ask about.

## Which cycle a backfilled term belongs to

A term's cycle is read from the days the person's votes were cast, not from when their row was last written.

An earlier backfill read the cycle off `last_seeded_at`, so re-seeding an old
row dragged that person's term into the current cycle. The votes are evidence
of when somebody was serving; a seeding timestamp is evidence of when a script
last ran.

`CorrectTermYearsFromVotes` applies the same evidence to legacy term rows only
when their roll-call dates prove one cycle; its migration fixtures attach each
vote to the term under examination.

## Declared calendars

TermRules separates a jurisdiction's legal calendar from what its roster can prove. Undeclared calendars refuse rather than silently borrowing Baltimore's convening date.

The registry keeps citations with the declarations because the dates govern
every vote-to-term assignment. cycle_anchor_year names a real cycle start;
cycle_years supplies the default length, with a senator's six-year term passed
separately from Congress's two-year default. CongressTermHistory reads the
named Congress declaration without needing a database locale row.

Congress convenes January 3 under Amendment XX section 1. Maryland uses the
second Wednesday in January under Constitution Article III section 14.
Baltimore uses the Thursday after December's first Monday under Charter
Article III section 2(a)(2), including for its mayor. The mayor's legal start
is Tuesday under Article IV section 1; the shared rule remains a deliberate
limitation because Baltimore supplies no individual roll calls affected by
that two-day difference. These declarations retain the source review they
already carried; this naming change does not reverify the law.

publishes_exact_term_dates records source capability even where no reader yet
uses that flag. It does not replace the stored began_on or ended_on dates.

### Current roster rows can supply today's term

A current-member roster row can establish the term running now from its locale calendar, but it does not establish exact service dates or earlier terms. A roster with no term years can therefore retain an existing term without inventing past service.

### Who says when a term began or ended is recorded, not flattened

Both ends of a term take the same two answers — the jurisdiction published the
day, or Sway inferred it — and which one applies is stored rather than
discarded.

Flattening them would make a date Sway worked out indistinguishable from a date
the jurisdiction stated, and the two carry different weight when a roll call
has to be attributed to a person. Keeping the source is also what lets a later
publication of the real day replace an inference without having to guess which
dates were inferences.

## Roster evidence for observed departures

Absence from a roster no longer establishes departure dates. Missing officials cause no term-date write, score recomputation, or representative reassignment; instead, missing official evidence is logged.

Congress publishes term history through a separate source. History corrections
require that capability because a partial roster cannot establish the whole
past. Exact dates can override the year-based window; without them a window
ends at the successor's convening date, excluding that date from the old term.

`RetireDepartedLegislatorsService` previously recorded the observation day as
an inferred `ended_on` date with source `observed`. Sway no longer derives
departure dates from a missing name in complete, incomplete, or repeated roster
downloads. When an official is missing from a roster, the service logs the absence
and the missing official departure date evidence without mutating term dates.
Existing data remains intact; neither score recomputations nor representative
reassignments are triggered.

The former reappearance-clearing method logs without changing stored dates.
Similarly, history correction in the full seeder preserves an existing stored
departure date and its source rather than clearing it when an incoming entry
names the member as current. Reappearance in a roster, whether accompanied by
service history or not, never clears a stored departure date. Both inferred
(`observed`) and officially evidenced (`published`) departure dates are preserved
byte-for-byte across repeated imports, and a current-member flag alone does not
restore serving status when a departure date is stored. Correcting an established
departure date requires the planned manual repair process. The broader protection
against historical date changes and term deletion also remains planned work.

The service retains its `retire_departed_members` logging keys so operational
event monitoring remains consistent.

## Departure safeguards

Missing roster entries can represent a truncated fetch rather than real vacancies. The caller's size floor and the service's departure limits guard different failure shapes.

The caller skips departure audits and reconciliation for an empty or implausibly
small roster. The service then bounds unreplaced departures by the larger of
three people or five percent of the serving body, rounded down. Real new arrivals
offset departures so an election can replace many seats without looking like a
truncated fetch. Arrivals count only identities unmatched in the database;
relisting incumbents cannot make missing people believable.

A seen identity accounts for its person. An unidentified entry that resolves
to a known occupied seat conservatively accounts for its occupant; that seat
never establishes that two named people are the same person. An unresolved
entry could represent anyone, so the entire departure audit pass refuses.

Refusals are logged and reported to Sentry because a seed can otherwise decline
silently. Believable departures log missing official departure date evidence for
each missing member; because missing names no longer establish departure dates,
no term dates are mutated and no retirements are performed.

## Roster identity during seeding

TermRules identified_by distinguishes person identifiers from seat identifiers. A seat-keyed source needs the published name with the seat to distinguish successive occupants.

### Identity is a table of rows, not one column

Each person's identity to each source is a row of locale, source and value
pointing at the legislator, and many rows may name one person.

One column per legislator works for a source publishing an identifier per
person and breaks for one publishing an identifier per seat: a seat identifier
is republished after every election, so a successor found the previous
occupant's row and their name was written over the votes, the reader links and
the score history underneath it. Many rows to one person is also what lets
somebody keep a single record across a change of seat. The unique index is
scoped by locale as well as source, because two cities both running the same
software publish the same seat identifier and they are not the same seat.

Baltimore's source lists only today's occupants. Its departure flag could
become true once seat-plus-name identities made a replaced occupant disappear
from the incoming identity set. A blank-name seat row
does not identify a person and is kept as an unidentified entry; seeding it
would erase the incumbent's name.

SeedLegislator selects its preparer from the declared roster source with no
fallback. It records every seen identity before the hand-edit guard, including
people whose attributes will not be rewritten. Malformed rows raise SeedError
with locale and identity context so a failed import remains diagnosable.

Person lookup first uses LegislatorIdentifier. A successor must get a separate
person row so existing votes and reader links remain with the former occupant.
The fallback lookup uses the unique locale and external_id pair to recover
rows missing an identifier; otherwise a migration-created person could trigger
a duplicate insertion during boot. Recording the identifier repairs that gap.

Seat and title facts belong to terms. The hand-edit guard protects person
attributes only; term seeding runs outside it because unrelated timestamp
changes must not prevent importing legislative history. Reconciliation is
enqueued once per locale after the roster floor passes and can be repeated
safely; the job derives user districts from addresses and isolates failures
per user instead of putting that rescue in the service.

### Configured office metadata for current seat-keyed rosters

A title-to-chamber map lets configured current rosters establish distinct office metadata without claiming exact service dates.

The `term_rules.seat_chambers` mapping opts selected titles into configured chamber metadata across both seat-keyed rosters (such as Baltimore) and person-keyed rosters (such as Congress and Maryland), as described in [[lat.md/explanation/representative-resolution.md#Configured seat identity for person-keyed rosters]]. [[db/seeds/models/seed_legislator_terms.rb#SeedLegislatorTerms]] persists that office's district-scoped seat for an active prepared member in the current term window, after validating the prepared district and matching locale-scoped identity. For person-keyed rosters, seed preparers supply deterministic office identities—such as Congress single-member House districts and constitutional Senate classes in state district zero, and Maryland statewide executives in MD0, single-member Senate districts, and co-serving Delegate slot keys in MD1 through MD47—allowing offline seed ingestion and sub-second container boot. A matching current term receives its missing seat; conflicting seats and metadata are refused. When another person's term overlaps the same office, the new person's row remains separate but seatless and the unresolved assignment is logged. The map establishes office identity, not published service dates, and leaves the exact [[official-service-evidence]] path unchanged.

## Missing source fields preserve stored roster values

A refresh overlays incoming fields onto the same person's committed roster entry. Source silence preserves stored values; an explicitly supplied value, including nil, blank text, false, or an empty array, replaces them.

BaseRefresh applies this contract to Baltimore, OpenStates, and Congress before
writing or uploading JSON. The baseline is the locale's canonical seed file,
not the live Legislator table. This protects the existing file-based refresh
workflow while database refresh remains separate planned work, with its intended
behavior described in [[current-legislator-term#Planned automatic legislator updates]].

[[app/services/legislators_cache/base_refresh.rb#BaseRefresh#call]] applies this
merge before writing the refreshed JSON and returning changed files. The
call-path photo regression checks the returned JSON itself, because the private
merge examples alone do not prove that refresh publication retains the photo.

Matching follows the seed identity rules: Congress bioguide IDs, OpenStates
person IDs, or the curated locale's declared identity scheme. Baltimore needs
the seat plus a normalized published name. A successor or unnamed seat inherits
nothing from its previous occupant. Only incoming people are returned, so this
merge cannot undo observed departures or add back a missing roster member.
Invalid JSON, a non-object roster shape, or duplicate stored identities raises
instead of silently selecting or discarding someone's stored details.

Nested objects merge by key so an attribution-only depiction update preserves
imageUrl, and a missing terms property preserves that property. Arrays replace
as a unit; term histories from separate responses are never blended. Curated
field aliases follow the spellings accepted by the seed preparer. Supplying any
photo spelling removes stored photoURL, photo_url, and photoUrl before the new
value is applied, so an older higher-priority alias cannot defeat a clear.
The same rule covers the preparer's name, external ID, region, postal code,
and term-year aliases. Congress updateDate remains excluded as volatile metadata.

### Baltimore source presence

Baltimore builders omit fields their sources do not publish. Missing ArcGIS contact properties preserve stored contacts, while properties explicitly present as nil or blank clear them.

ArcGIS names district council members, Legistar names the current council
chair, and Wikidata names the mayor. None supplies the stored photos or Twitter
handles; manufacturing photoUrl nil would incorrectly erase them. The executive
builders likewise omit unsourced email instead of manufacturing an empty string.
Office phone numbers and links remain declared facts about the office, stable
across occupants. ArcGIS has no term dates, so missing years retain stored
values or use the seed calendar for a new person.

A district without AREA_NAME is logged and skipped because inventing MD0 would
assign the wrong constituency. An unresolved council chair remains an unnamed
seat with a warning; it receives no stored person fields. A missing mayor raises
because the source did not establish a current occupant. BaltimoreSeatKeys keeps
office and district identifiers consistent across refresh and seeding.

The refresh regression rebuilds source projections from the checked-in public
Baltimore roster and verifies all 16 photos and 12 Twitter handles survive.
Separate cases cover explicit clearing, successor isolation, nested Congress
fields, OpenStates person identity, and legacy alias precedence.

## Planned automatic legislator updates

Routine updates to the list of elected officials are planned to run automatically from official sources. Corrections to previously stored service dates and their effects on scores initially require manual control.

These are planned requirements, not claims that the current refresh enforces
them. Routine changes need no administrator approval queue. Separate tasks
cover automatic updates and the exceptional historical repair interface.

Official sources establish identity, office, and service dates: Baltimore
Legistar, congress.gov, and the Maryland General Assembly's official website.
Current readers of OpenStates or other third-party information do not yet
satisfy this requirement. A recently downloaded list of elected officials
cannot establish a departure date merely by omitting a name. Sway waits for
an official source to establish the specific date a legislator left office.

A predecessor must leave a seat before a successor holds it. Vacancies are
acceptable; overlapping occupants of the same seat are not. This applies to
successive occupants of one office, not different seats sharing a district.
Conflicting official sources pause automatic changes for the affected seat.
Sway records the conflict and retries using the official source appropriate
to each fact. The display during an unresolved conflict still needs definition.

A historical vote naming an unknown person can trigger automatic retrieval
of their identity, seat, and service history from official sources. Creation
requires evidence for those facts. Missing evidence leaves the vote unresolved
and the coverage gap visible. A historical vote naming only an office follows
the same rule: other verified votes remain, and today's officeholder cannot
substitute for an unidentified historical officeholder.

Corrections to stored service dates are exceptional across all sway locales.
Their effects on legislative votes, user scores, and users' representative
assignments require a manually controlled repair process initially. The repair
needs an explanation and an audit trail, including source evidence, old and new
values, affected records, authorization, and execution results. A reviewable
account of the effects precedes authorization; user scores cannot change
silently through routine updates. The planned admin tool below provides this
review. The presentation of explanations to affected users remains to be designed.

### Officially supported title completion

Official service evidence may complete a blank title when it identifies the same term.

The fact must match the stored term's typed person identity, locale, district, office identity, and exact start and end dates. Under a row lock, the writer changes only the title. Unsupported or ambiguous facts and nonblank titles remain unchanged. The locale caller reuses its fetched result through [[app/services/executive_title_fill_service.rb#ExecutiveTitleFillService]] and [[db/seeds/models/seed_legislator_terms.rb#SeedLegislatorTerms]].

### Presidential display

The President appears as a serving or historical officeholder only when official evidence identifies the person, office, exact service bounds, and stable office identity.

The selected model uses an ordinary [[app/models/legislator_term.rb#LegislatorTerm|legislator term]] so the President follows the same date-bound current and historical display rules as other officeholders. Its interval includes the evidenced start and excludes the end, matching [[app/models/term_window.rb#TermWindow]]. Outside that interval, [[app/serializers/legislator_resource.rb#LegislatorResource#display_term]] may show it as historical. A person row or an office label alone does not establish service, and the presidential office does not imply congressional floor votes.

[[db/seeds/models/legislator.rb#SeedLegislator#run]] passes configured official service evidence to [[app/services/official_evidence/seed_service.rb#OfficialEvidence#SeedService]]. A supported exact term then follows the existing list and display path in [[app/controllers/legislators_controller.rb#LegislatorsController#build_json_legislators]] and [[app/serializers/legislator_resource.rb#LegislatorResource#display_term]].

The example is a presidential record whose official source supplies the person's identity, the specific office, an explicit office title, and exact start and end dates. It qualifies for current display only while those dates cover today. An unrelated person row with no running or historical term remains excluded, even if that row is marked active in a roster. Both examples preserve the boundary between office evidence and a guessed identity.

The generic service reader and seed path implement this contract with retained exact evidence. Current Congress configuration declares no verified live service profile, so presidential initialization remains explicitly unsupported. The committed roster sentinel and chamber label alone cannot establish service. Missing evidence leaves the office absent and creates no civic records; [[official-service-evidence#Capability is explicit]] owns the source capability rules.

Seeding transactionally retires un-evidenced executive sentinel terms that lack a seat identity, title, and legislative votes when official service evidence is unsupported. This removes unseated terms from the locale-wide district US0 and its score families so representative resolution does not raise errors, while keeping the underlying person, identifier, and user-link records intact until authoritative service evidence is configured. Conversely, when official service evidence is supported, evidenced presidential terms and seats are seeded and preserved.

### Planned admin tool for historical repairs

A dedicated tool in the admin suite previews every intended repair change and its effects on users and scores before authorization. Generating the preview leaves live civic records and scores unchanged.

The preview names the legislator, seat, sway locale, and affected dates. It
shows the stored and corrected service dates, official source evidence, and
the reason for the correction. It lists every record to create, change, or
remove, including affected legislative votes and users' representative
assignments. Any resulting notifications or other user-visible effects are
included in the preview.

Score effects include affected users and the before-and-after values for each
affected score, with a plain-language explanation of the difference. Summary
counts lead to the complete details. Historical scores and former representative
assignments are included wherever affected, consistent with
[[scores-and-agreement#The one-time repair walks every term, not only the current one]].

Authorization applies to the exact preview the administrator reviewed. Changes
to relevant records or source evidence require a fresh preview before execution.
An incomplete impact calculation prevents authorization rather than presenting
unknown effects as zero changes. An overlapping occupant of the same seat also
prevents authorization.

The audit trail retains the preview, evidence, authorizing administrator, and
execution results. The tool shows progress and failures and compares actual
results with the authorized changes. Detailed layout and recovery behavior
remain implementation decisions; this section describes planned requirements.

### Historical repair explanations

A historical score explanation communicates how an authorized service date correction affected user-visible scores.

[[app/models/historical_score_explanation.rb#HistoricalScoreExplanation]] links an affected user and optional legislator to the audit trail records of an authorized repair preview. The model captures the score type, title, and explanatory body text explaining the adjustment, ensuring historical corrections remain transparent without recomputing scores during presentation in web and mobile term views.

### Planned implementation stages

Shared official evidence and write checks precede automatic updates and historical repairs. Separate implementation tasks prevent either workflow from undoing the other.

One legislator-updates parent epic groups the six stage epics: official evidence,
automatic updates, historical officeholder matching, agreement by recorded term,
the admin repair tool, and authorized repairs. Each stage retains its own
prerequisite links and discrete implementation tasks. The parent tracks completion
of those stages and adds no independent implementation.

The shared prerequisites establish official source capabilities, retain source
evidence, identify specific seats, and reject overlapping occupants. They also
stop changes to established service dates or historical vote records from
silently changing scores. Source assessments remain separate from the readers
that implement their findings.

Score calculation fixes and nullable vote-term storage precede repair previews.
The compatible vote lookup and uniqueness constraints must support the first
repair without requiring that repair to have already filled every association.
The later requirement that every stored vote have a term waits for an actual
authorized repair and refuses when official evidence still leaves gaps.

Historical matching tasks supply official evidence and select affected records.
The admin tool's shared calculators determine exact vote, assignment, score,
and message changes. Input selection tasks do not implement second calculators.
Any required person, identifier, or term creation also appears in the complete
preview; it cannot occur through a separate live import during preview.

Using the completed tool on production is separate work. Each operation starts
from remaining discrepancies after earlier repairs, requires a fresh preview
and administrator authorization, and records results through the common audit.
A staged rehearsal does not establish that production records were corrected.

## Refresh comparison and publication

Refreshers compare parsed JSON against the canonical seed file and publish only meaningful changes. Every successful fetch stamps freshness, including one whose roster is unchanged.

The six-day freshness cutoff allows a weekly job to run slightly earlier than
last week's start without skipping a whole week. Force bypasses the cutoff.
Parsed comparison ignores indentation; raw text comparison remains the fallback
for invalid comparison input. A missing baseline counts as a change. Congress
removes updateDate from output and comparison because it changes independently
of roster facts and no seed preparer reads it.

Canonical seed paths use the locale's reversed jurisdiction components, matching
the seeder. GCS stores a canonical object and a timestamped archive under the
full locale name so cities in different states cannot overwrite each other.
Result changed_files maps repository-relative seed paths to the generated JSON;
an empty map gives the caller no roster change to propose.
