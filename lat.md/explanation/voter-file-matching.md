---
lat:
  mode: explanation
---
# Matching Sway users against the Maryland voter file

A legislator wants to know whether the people behind Sway's numbers are registered voters in their district. A checkbox records that claim; matching Maryland's own list is the only way to check it. This is what that would take.

Everything below was checked against public sources on 5 September 2026. Where
a fact could not be established from a public source it is named as a gap
rather than estimated.

The short answer is that Maryland does not sell its voter list for this. The
law that governs the sale confines use to the electoral process, and a running
civic platform checking its own signups is outside that. The data question —
how much other people's personal data Sway would hold — is the second reason,
not the first.

## How the list is obtained

The Maryland State Board of Elections holds the registration files of all
twenty-four local boards and sells lists from them. A written application and a
sworn statement about intended use precede any copy leaving the board.

Eligibility is narrow. Election Law § 3-506(a)(1) allows a copy to go to a
Maryland registered voter, on a written application together with "a statement,
signed under oath, that the list is not intended to be used for: 1. commercial
solicitation; or 2. any other purpose not related to the electoral process."
A company is not a registered voter. An application would therefore stand in
the name of an individual person, who signs the oath and carries the criminal
exposure described below.

The board's own page describes an online or printed application, payment before
processing, delivery within ten working days of both arriving, and delivery by
file transfer, by a flash drive in the post, or by collection in person. It
also states that applications have to arrive on or before the advance
registration deadline — twenty-one days before an election — or after election
day, and that anything arriving inside that window is returned.

The board excludes participants in the state's address confidentiality
programme: their residence addresses are not disclosed on a purchased list, and
they do not apply separately to keep that protection.

Sources checked 5 September 2026:
- <https://elections.maryland.gov/voter_registration/data.html>
- <https://mgaleg.maryland.gov/mgawebsite/Laws/StatuteText?article=gel&section=3-506&enactments=false>
- <https://elections.maryland.gov/pdf/SBEAPPL.pdf>

## What it costs

The purchase price is small enough that it decides nothing. The board's
published prices are $125.00 for a statewide list and $75.00 for a single
county, district or municipality list.

Sway's three locales map onto those products unevenly. Baltimore City is one
county-level list at $75.00. Maryland statewide is the $125.00 product. The
congressional locale covers the same population as the statewide list, so it
needs no separate purchase for Maryland residents, although it covers only
Maryland — a national congressional picture would mean repeating this exercise
in every other state, each with its own statute, its own price and its own
answer.

Registration data goes stale continuously, so a single purchase describes one
day. Keeping a match current would mean repeat purchases on some cadence, at
the same price each time, plus the standing engineering cost of ingesting and
re-matching. Whether a subscription arrangement exists at a different price was
not established from public sources.

Source checked 5 September 2026:
<https://elections.maryland.gov/voter_registration/data.html>

## What the terms of use allow and forbid

This is the section that ends the idea. Maryland restricts the purchased list
to the electoral process by statute, backs that with a sworn statement and a
criminal penalty, and the board separately forbids using the data to
investigate voters.

Election Law § 3-506(c) provides that "A person who knowingly allows a list of
registered voters, under the person's control, to be used for any purpose not
related to the electoral process is guilty of a misdemeanor and, on conviction,
is subject to the penalties under Title 16." Where no specific penalty is set,
Election Law § 16-1001 supplies a fine of not less than $10 and not more than
$250, or imprisonment of not less than thirty days and not more than six
months, or both.

COMAR 33.03.02.01B defines the boundary: "Electoral process" includes, but is
not limited to, registering voters, forming political parties, qualifying as a
candidate for public office, petitioning candidates or questions to the ballot,
drafting and publishing ballot questions, conducting elections, casting
ballots, canvassing ballots, recounting an election, and financing a campaign.
The list is open-ended, so it does not settle every case on its face. It also
does not contain anything resembling a platform confirming that its own account
holders are registered, and the board's purchase page states plainly that the
data is not to be used "for investigations into an illegal or suspected illegal
infractions or violations of voters' behaviors" — checking a person's
registration status against a claim they made is close to that description.

Two further points bear on Sway specifically. Commercial solicitation is named
in the oath, and Sway is a product with commercial character even where the
feature itself sells nothing. And the oath is sworn by a named individual, so
the risk of a wrong reading of "electoral process" falls on that person
personally, not on the company.

Whether the State Board has ever approved a use resembling this one could not
be established from public sources. No published advisory opinion, guidance
letter or enforcement record addressing platform-side verification was found.
That gap matters: the honest position is that the terms appear to forbid this
use and that the board is the only body that can say otherwise.

Sources checked 5 September 2026:
- <https://mgaleg.maryland.gov/mgawebsite/Laws/StatuteText?article=gel&section=3-506&enactments=false>
- <https://codes.findlaw.com/md/election-law/md-code-elec-law-sect-3-506/>
- <https://www.law.cornell.edu/regulations/maryland/COMAR-33-03-02-01>
- <https://codes.findlaw.com/md/election-law/md-code-elec-law-sect-16-1001.html>
- <https://elections.maryland.gov/voter_registration/data.html>
- <https://www.stmaryscountymd.gov/supervisorofelections/purchase/>

## How names and addresses would be matched

Matching would join two records that share a person's name and home address and
nothing stronger. The registration list carries more identifying columns than
Sway holds, and the columns Sway lacks are the ones that make a join safe.

The board's application form describes the registered voters list as carrying
name, party, date of birth, gender, residence address, mailing address, active
or inactive status, state and county registration dates, precinct and split,
and congressional, legislative, councilmanic, ward, municipal and commissioner
districts, delivered as text files. That field list comes from search-index
extraction of the application PDF rather than from reading the document
directly, so the exact layout is worth confirming with the board before any
work depends on it.

Sway holds a person's full name on the user row and a street address, unit
lines, city, region, postal code and geocoded coordinates on the address row.
It holds no date of birth and no gender. The join is therefore name plus
address alone.

The strength of that join is documented. Ansolabehere and Hersh's ADGN work
reports that address, date of birth, gender and name together identify a person
about as reliably as a nine-digit Social Security number, and their argument is
built on the four elements together rather than on any pair. Dropping date of
birth and gender removes two of the four. What remains fails in both
directions: a household where a parent and an adult child share a first name,
or two unrelated people with a common surname in a large apartment building
with no unit recorded on one side, produce false matches; and a nickname, a
married name, a middle name present on one side only, a recent move, or an
apartment number formatted differently produce misses.

A specific match rate and false-match rate for this pairing could not be
established from public sources, and no number is offered here. What is
established is the direction: name-and-address-only linkage is materially
weaker than the four-element linkage the literature treats as reliable, and the
errors it makes are individually consequential, because each one either tells a
legislator that a real constituent is not registered, or tells them that
someone is registered on the strength of a coincidence.

Sources checked 5 September 2026:
- <https://www.tandfonline.com/doi/full/10.1080/2330443X.2017.1389620>
- <https://elections.maryland.gov/pdf/SBEAPPL.pdf>

## What new personal data Sway would hold

A purchased list is not a lookup service. It arrives as a bulk file, so holding
it means holding a record for every registered voter in Maryland, almost all of
whom have no relationship with Sway and never consented to anything.

For each of those people the file carries a legal name, a home address, a
mailing address, a date of birth, a gender, a party registration and a set of
district assignments. Party registration and date of birth are both categories
Sway has deliberately never collected. The exact statewide registration count
was not established from public sources; the relevant fact is the shape, which
is every registered voter in the state.

For Sway's own users the result would be a stored verdict — matched, unmatched,
ambiguous — which is itself a new and sensitive fact about a named person, and
one that is wrong some of the time for the reasons above.

This sits directly against the direction of the work this page belongs to. That
branch encrypts names, phone numbers, email addresses, street addresses and
coordinates precisely to shrink what a database compromise would expose. A bulk
voter file would enlarge that exposure by orders of magnitude, and the enlarged
part is other people's data, held without their knowledge, which no amount of
column encryption makes less of a holding. It would also make Sway a more
attractive target than it is today, and it would create a retention and
deletion obligation for records belonging to people who cannot be contacted.

## The trade-off and the recommendation

The purchase is cheap and the engineering is ordinary. The two costs that
matter are legal exposure that falls on a named individual, and a large holding
of personal data belonging to people who never signed up.

Against that stands a bounded benefit. A name-and-address match returns a
probabilistic verdict, not a fact, and a legislator shown "eighty-one per cent
of these voters are registered in your district, give or take our matching
error" is not obviously better served than by a clear statement of how many
people affirmed the registration claim themselves.

The recommendation is that Sway does not pursue voter file matching. The
blocking reason is the terms, not the data volume: Maryland confines the
purchased list to the electoral process under a sworn statement backed by a
criminal penalty, and forbids using it to investigate voters, and platform-side
verification of a service's own account holders does not fit inside that. The
data-holding argument is independent and points the same way while this branch
is reducing exposure rather than adding to it.

The self-attestation approach on the address form remains the right
mechanism. Its honest description is that a person stated their registration
address, and stating that plainly to a legislator is more defensible than a
matched percentage carrying an unmeasured error.

One path could reopen the question, and only one: a written determination from
the State Board of Elections that this use falls inside the electoral process.
Until such a determination exists, the reading above stands, and it was
reached from the published statute, regulation and board terms rather than from
legal advice.
