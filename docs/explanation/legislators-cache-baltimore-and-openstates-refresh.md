---
mode: explanation
summary: "Why BaltimoreRefresh builds the roster entirely from live sources with no hand-written district map, why a seat's identity is split from the person who fills it, and why OpenStatesRefresh dedupes hand-declared executives against the API's own answer."
status: agent-extracted
related: []
---

<!-- vale Vale.Spelling = NO -->

# Why `BaltimoreRefresh`, `OpenStatesRefresh`, and `BaltimoreSeatKeys` are built the way they are

## Why Baltimore's roster has no hand-written district map

`BaltimoreRefresh` builds the current Baltimore roster entirely from live
sources the city keeps up to date — no hand-written district map, no
names typed into the code, no scraping of web pages:

- **District council members (MD1-MD14)** come from Open Baltimore's
  ArcGIS "Baltimore City Council District" map layer. The city publishes
  exactly one tidy record per seat (name, district, phone, email, council
  URL) and republishes it after every election.
- **The Council President** is whoever currently chairs the council body
  in Legistar, the city's legislative records system, which tracks that
  role reliably.
- **The Mayor** comes from Wikidata's current head of government for
  Baltimore (entity Q5092).

The refresher fails loudly rather than seeding a stale name: it raises if
Wikidata lists no sitting Mayor.

## Why a Baltimore seat's identity is split from the person who fills it

The district council external_id is `"baltimore-district-{n}"` — the
SEAT, not the person. A seat alone cannot say WHO holds it, so the seeder
does not treat it as an identity on its own. It pairs the seat with the
name published under it (see `LegislatorIdentity`), and a successor
arriving under the same seat becomes a new person rather than a new name
tacked onto the previous occupant's votes. `BaltimoreRefresh`
keeps publishing the seat, because the seat is what the city publishes;
the pairing with a person is Sway's own, made when the roster is read.

`BaltimoreSeatKeys` is where the Mayor's, Council President's, and
Comptroller's external ids live, in one place, so the refresher and
everything else that reads a Baltimore seat (including the migrations
that rewrote existing rows) cannot drift apart. The Mayor and the Council
President serve the whole city and both sit under the stand-in district
`MD0`, so district cannot tell them apart — they are named by office
instead. `BaltimoreSeatKeys.seat_key?` answers false for rows predating
the seat-key change, which were named after the person (e.g. `"zeke-cohen-2020"`)
rather than the seat.

## Why council term years are estimated rather than fetched

The ArcGIS council district layer carries no term dates, so
`#build_council_entry` leaves them out and Sway's seeding code fills in
years from its usual election cycle instead. Those years are guesses, not
official — but they are safe guesses: they exist only to keep the
term-rollover guard from deciding a term ended the moment the first reseed
from live data lands, not to assert an authoritative term boundary.

## Why the office phone numbers and links are hardcoded

`MAYOR_PHONE`, `MAYOR_LINK`, `COUNCIL_PRESIDENT_PHONE`, and
`COUNCIL_PRESIDENT_LINK` are hardcoded constants rather than fetched
values, because Wikidata carries no contact details and these numbers
stay the same no matter who holds the office — they are facts about the
OFFICE, not roster data that goes stale with an election.

## Why `#build_council_entry` logs and skips rather than fabricating a row

When an ArcGIS council feature has no district number, `#build_council_entry`
logs a warning and returns nil, so a broken upstream record shows up in
the log instead of quietly seeding a made-up citywide `MD0` row that would
be wrong for a district seat.

## Why `#build_council_president_entry` writes a blank-name row rather than skipping

The Council President entry is written out even when Legistar cannot
resolve the sitting chair — with a blank name and a warning — so the
office row never disappears from the roster entirely. A missing office
row is a worse failure than a blank name, because downstream code expects
every declared office to have a row.

## Why the Comptroller has no source

The Comptroller is missing from the seed file entirely: that office is
not one of the elected bodies Legistar tracks, and nothing else publishes
it live yet.

## Why `OpenStatesRefresh#missing_executives` dedupes on two keys

`OpenStatesRefresh` (formerly `MarylandRefresh`, before which jurisdiction,
executives, and path were all locale-specific constants) adds hand-declared
executives (`SwayLocale::OpenStatesExecutivesRegistry`) only for the ones
the API response did NOT already return. Two things are compared: the
OpenStates id (the real identity key) and the family name plus role title
with punctuation stripped out. The id check does the real work; the title
check is a backstop that catches the case where the OpenStates API DOES
return an executive but spells the title differently (`"Lt_Governor"`)
than the hand-written entry (`"Lt. Governor"`) — without the backstop, a
locale whose declared executive later appears in the API's own results
would get a duplicate row in the seed.
