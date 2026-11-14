---
lat:
  mode: reference
  require-code-mention: true
---
# Seat chamber coverage tests

These specifications check every declared locale's seed roster against the seat chambers its locale document declares.

## Every roster title maps to a seat or a skipped office

Each roster entry's prepared title has a configured seat chamber, or the entry is an unconfigured executive office or the Congress President that the seeder keeps out of the term table, and each locale declares at least one chamber.

## Every seeded current term has a seat or an unconfigured office

After seeding every declared locale, each current term carries a seat unless its title has no chamber in a locale that declares chambers; a failure names the locale, title and term id.

## Title aliases reach the configured chamber

The State Delegate and State Senator aliases return the Maryland Delegate and Senator chambers.

## Blank and unknown titles have no chamber

A blank title, a nil title and an unconfigured title such as Attorney General return no seat chamber.
