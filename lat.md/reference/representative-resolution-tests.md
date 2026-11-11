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

### Refuses missing seat identity

A current selected term without a persisted seat identity raises before it can be linked.

### Selects the exact Congress locale-wide district

Congress resolves the configured `US0` district and does not mistake Maryland's `MD0` Senate seat for a nationwide office.

### Uses exact locale-wide names

The configured Congress `US0` seat is included, a same-numbered `OH0` office is excluded, and `MD0` remains eligible when geography selects district zero.

### Includes locale-wide occupants through geography

Congress adds its configured nationwide office alongside a district-zero representative selected by geography.

### Adds Maryland locale-wide seats to regional results

The configured `MD0` office resolves even when OpenStates returns no geographic candidate.

### Checks omitted current occupants

Every current row for a selected seat is checked even when the geographic endpoint omits an overlapping occupant.

### Rejects duplicate rows for one person

Duplicate overlapping current terms for one person and one seat are refused instead of being hidden by the singular active-term association.

### Leaves expired seats vacant

The exclusive end boundary removes the former occupant without inventing a successor.

## Reconciliation refusal

Resolution errors occur before reconciliation mutates stored representative links.

### Preserves links on unresolved reconciliation

Reconciliation raises on an unresolved current seat before deactivating stored legislator or district links.

### Preserves links on locale-wide conflict

An ambiguous configured locale-wide seat raises before reconciliation deactivates existing links.

### Refuses unseated locale-wide term

Reconciliation raises on a current locale-wide term lacking persisted seat identity before updating links.

## Reconciliation keeps co-serving seats

Reconciliation retains every current supported occupant in a district and applies locale-wide links idempotently.

### Keeps each active co-serving occupant

Two active links for separate current seats in one district stay active after reconciliation even when their term start years differ.

### Reactivates locale-wide link idempotently

Reconciliation reactivates an inactive nationwide-office link and its district link, then leaves both active on a second run.
