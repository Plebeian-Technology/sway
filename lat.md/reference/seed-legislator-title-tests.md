---
lat:
  require-code-mention: true
  mode: reference
---
# Seeded legislator title tests

Regression checks for official title fills during legislator seeding.

## Existing term title fill

Only a persisted blank title with exact matching person, office, district, and service dates accepts a supported official fact.

### Fills an exact supported title

An exact trusted fact fills only the existing term's blank title; unsupported or mismatched evidence leaves it unchanged.

### Preserves the term except for its title

The fill keeps dates, seat, term count, scores, votes, and assignments unchanged, and a repeated fill performs no write.

### Preserves a nonblank title

An older or less complete service entry cannot replace an existing title.

### Rejects unsupported or mismatched facts

An unsupported fact or a mismatch in person, office, district, or exact start/end dates leaves the blank title unchanged.

## New term seat mapping

New terms receive a seat only when the same exact supported service fact identifies their person, office, district, and interval.

### Persists the official interval and seat

A prepared exact official fact maps its explicit office identity to the district-scoped seat on the new term.

### Refuses mismatched official identity

An official fact for another scheme-qualified person cannot create a term for this legislator.

## Configured roster seat mapping

Checks for opt-in chamber metadata from a declared seat-keyed roster, including current-term, locale, identity, and persisted-seat guards.

### Allows configured seat chambers on person-keyed rosters

Document reading accepts term rules seat chambers on person-identified locales and loads Congress title-to-chamber mappings.

### Preserves published Senate class on terms

Congress term history extraction retains the published constitutional class on Senate terms and omits it on House terms.

### Attaches distinct seats for House and co-serving Senators

Current Congress seeding attaches a single-member seat for a House member and distinct constitutional class seats for co-serving Senate members in district zero.

### Attaches distinct seats for Maryland executives, senators, and delegates

Maryland seeding attaches distinct seats for the MD0 Governor, MD1 through MD47 state senators, and all co-serving delegates, and seeds nobody for the unmapped Lieutenant Governor and Attorney General offices.

### Persists a configured current office without claiming exact dates

A configured current roster row creates its declared district-scoped seat, while its term continues to use the locale calendar and has no exact published-date claim.

### Defers an overlapping successor seat

A differently identified person remains a separate roster record but receives no seat while another person's term overlaps; the existing occupant and civic history remain unchanged, and the unresolved assignment is logged.

### Waits for the actual current term window

A current-member flag does not create a seat before the prepared term's locale calendar window begins.

### Skips inactive prepared entries

An inactive entry cannot assign a seat to a stored current term merely because its calendar range is still running.

### Rejects a cross-locale prepared district before writes

A configured seat path refuses a prepared district from another locale before creating a term or seat.

### Refuses an unmapped title and malformed office key

A configured roster mapping refuses a current title without chamber metadata and an identity that contains no valid declared office key.

### Requires the prepared identity to belong to the legislator

A seat is not created when the locale-scoped identifier resolves to a different legislator, even when the prepared name matches.

### Repairs only a matching current nil-seat term

Only the matching current prepared term may receive a missing seat; historical terms, votes, scores, and date metadata remain unchanged.

### Preserves a seat assigned after selection

A seat assigned after the nil-seat candidate is selected remains persisted, and the seed refuses to replace it with a different office.

### Refuses mismatched current metadata and a conflicting persisted seat

A current term with mismatched metadata or a different persisted seat is refused without changing its existing seat or metadata.

## Executive title caller

The executive caller reuses one official service result and the shared title writer.

### Uses a supplied locale result once

The caller does not fetch again when seeding already supplied the locale's result and changes only the matching blank term title.

### Rejects duplicate exact facts

Duplicate official facts for the same person, office, district, and exact interval leave the existing title unchanged.
