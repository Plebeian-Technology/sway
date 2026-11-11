---
lat:
  mode: explanation
---

# Why BaltimoreSeatKeys keys seats by office

Why municipal seat identities are keyed by office rather than officeholder, and how Baltimore seat identifiers remain stable across elections.

## Why a Baltimore seat's identity is split from the person who fills it

The district council external ID is "baltimore-district-{n}", identifying the seat rather than the person.

A seat alone cannot identify who holds it, so the seeder does not treat it as an identity on its own. It pairs the seat with the name published under it (see [[legislator-identity-value-design#Why seat_and_name returns nil on a blank published name]]), and a successor arriving under the same seat becomes a new person rather than a new name tacked onto the previous occupant's votes. The curated roster records each seat key, while the pairing with an occupant occurs when Sway reads the roster.

[[app/services/legislators_cache/baltimore_seat_keys.rb#LegislatorsCache#BaltimoreSeatKeys]] defines external IDs for the Mayor, Council President, and Comptroller in one place so the seeder, cache operations, and migrations cannot drift apart. The Mayor and the Council President serve the whole city and both sit under the stand-in district MD0, so district cannot distinguish them; they are named by office instead. BaltimoreSeatKeys.seat_key? returns false for rows predating the seat-key change, which were named after the person (such as "zeke-cohen-2020") rather than the seat.
