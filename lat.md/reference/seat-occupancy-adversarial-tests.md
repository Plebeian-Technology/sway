---
lat:
  require-code-mention: true
---

# Seat occupancy adversarial tests

These independent checks verify refusal and transaction behavior for writes to an already resolved elected seat.

## Nonpositive service intervals refuse

An evidenced seat cannot acquire a zero-length or reversed service interval, so invalid bounds leave the term table unchanged.

## Direct interval changes roll back on overlap

A direct date write that intersects an adjacent successor raises and restores the stored interval rather than committing the conflicting date.

## Normal writes retain a resolved seat

An ordinary update cannot silently remove an established seat identity and evade occupancy checks.

## Direct writes retain a resolved seat

The direct-column write path cannot silently remove an established seat identity and evade occupancy checks.

## Direct person changes retain locale ownership

A direct-column write cannot assign a resolved seat to a person belonging to another locale; the original person association survives the refusal.
