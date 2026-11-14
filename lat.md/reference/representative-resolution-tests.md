---
lat:
  mode: reference
  require-code-mention: true
---
# Representative resolution tests

These specifications protect distinct seat resolution and locale-wide membership.

## Registration seat resolution

The resolver specs prove every supported seat selection rule before user links are written.

### Resolves state delegation of senators and house representative

Registration resolves both co-serving Senate class seats in district zero and the single-member House seat for an address in the state.

### Resolves Maryland statewide executives and district delegation

Registration resolves the MD0 Governor (and not the unseeded Lieutenant Governor or Attorney General), the district state senator, and all co-serving state delegates for a Maryland address without unresolved seat errors.

### Retains co-serving distinct seats

Two currently serving seats in one geographic district both resolve even when their service years differ.

### Returns all supported delegates in one district

Every supported delegate seat returned by the Maryland regional source remains available to registration when several delegates share one district.

### Skips missing seat identity

A current geographic candidate without a persisted seat identity is left out, recorded once as `Seats::UnresolvedSeatError` and reported to Sentry at warning level, while the seated senator still resolves.

### Skips a seat outside its district

A current term whose seat belongs to another district is left out, recorded once as `Seats::UnresolvedSeatError` and reported to Sentry.

### Skips unconfigured locale-wide offices

A current unseated Maryland Attorney General term in `MD0` is left out without a recorded error or Sentry report, and the configured Governor still resolves.

### Skips unconfigured geographic offices

An unconfigured office holder returned by the regional source is dropped without a recorded error or Sentry report.

### Skips untitled unseated terms

An unseated locale-wide term with no title is left out, recorded and reported, because an absent title cannot show the office is unconfigured.

### Selects the exact Congress locale-wide district

Congress resolves the configured `US0` district and does not mistake Maryland's `MD0` Senate seat for a nationwide office.

### Uses exact locale-wide names

The configured Congress `US0` seat is included, a same-numbered `OH0` office is excluded, and `MD0` remains eligible when geography selects district zero.

### Includes locale-wide occupants through geography

Congress adds its configured nationwide office alongside a district-zero representative selected by geography.

### Adds Maryland locale-wide seats to regional results

The configured `MD0` office resolves even when OpenStates returns no geographic candidate.

### Checks omitted current occupants

Every current row for a selected seat is checked even when the geographic endpoint omits an overlapping occupant; both occupants are dropped and one `Seats::OverlapValidator::OverlapError` is recorded and reported.

### Drops duplicate rows for one person

Duplicate overlapping current terms for one person and one seat drop that person and record one `Seats::OverlapValidator::OverlapError`, instead of being hidden by the singular active-term association.

### Leaves expired seats vacant

The exclusive end boundary removes the former occupant without inventing a successor.

### Skips an unseated successor

A Baltimore successor seeded under a renamed office with the same published id has no seat yet; resolution returns the previous holder, leaves the successor out, and records and reports one `Seats::UnresolvedSeatError`.

### Registers around a skipped term

Synchronous registration in that state links the seated officers only, never the unseated successor, and completes the user.

### Resolves a seated successor

Once the previous term ends and the successor's term holds the seat, resolution returns the successor and records nothing.

### Resolves curated person-keyed officers

A seeded Annapolis address in districts 0 and 1 returns the Mayor and the Ward 1 Alderperson, because their curated terms carry seats, and records no skip.

### Resolves the seeded Baltimore roster

Registration against the seeded Baltimore roster, with the shipped council boundaries, returns the Mayor, the Council President and one Council Member for City Hall, and reconciliation keeps the same links.

### Resolves the seeded Congress roster

Registration against the seeded Congress roster for a Maryland address returns two Senators and one Representative and no President, and reconciliation keeps the same links.

## Reconciliation refusal

A recorded resolution skip refuses reconciliation before it mutates stored representative links.

### Preserves links on unresolved reconciliation

Reconciliation raises on an unresolved current seat before deactivating stored legislator or district links.

### Preserves links on locale-wide conflict

An ambiguous configured locale-wide seat raises before reconciliation deactivates existing links.

### Refuses while a term is skipped

Reconciliation raises the recorded `Seats::UnresolvedSeatError` while a Baltimore successor term is skipped, and leaves a stored council link active.

### Refuses unseated locale-wide term

Reconciliation raises on a current locale-wide term lacking persisted seat identity before updating links.

## Address switch around a skipped term

An address switch skips an unresolvable term like registration does, and changes no stored link for the skipped legislator.

### Keeps the skipped legislator's links

The legislator and district links of a skipped locale-wide term stay active, while the other stale links are deactivated and the new seated link is activated.

## Reconciliation keeps co-serving seats

Reconciliation retains every current supported occupant in a district and applies locale-wide links idempotently.

### Keeps each active co-serving occupant

Two active links for separate current seats in one district stay active after reconciliation even when their term start years differ.

### Reactivates locale-wide link idempotently

Reconciliation reactivates an inactive nationwide-office link and its district link, then leaves both active on a second run.
