---
lat:
  require-code-mention: true
---

# Official service evidence tests

These tests pin the generic service contract from source read through atomic civic writes.

## Immutable evidence keeps its payload digest

Persisted evidence rejects mutation and a mismatched payload digest, preserving the source response behind every supported fact.

## Configured reader returns exact facts

The reader requires an explicit profile, validates the actual response URL and exact ISO service dates, and retains source attribution for each supported fact.

## Vacancy differs from a failed source read

A source-published vacancy is retained as a vacant office fact without a person or dates; an HTTP failure produces a coverage gap instead.

## Official service facts seed through the existing term writer

Supported exact facts create a typed person, office seat, and term without vote rows, while ambiguous overlapping occupants are refused before civic writes.

### Fresh official service fact creates a person and term without votes

A fixture-backed service response flows through the existing term writer with a source-qualified identity and exact office bounds.

### Conflicting facts for one seat are refused together

Overlapping people cannot make one office appear to have an arbitrary occupant, so neither conflicting record creates civic rows.

### Unrelated source identifiers do not collide

An official service person with a raw identifier already used by another source remains a distinct typed identity.

## Unsupported President remains absent on a fresh installation

The current locale configuration has no verified service profile, so a legacy presidential roster sentinel creates no person record and the reader request contains no President.

## Unevidenced executive terms are retired when official evidence is unsupported

Seeding transactionally removes un-evidenced executive sentinel terms and dependent scores while keeping identity and reader links intact.

### Unevidenced POTUS term in US0 is retired when official evidence is unsupported

Seeding under unsupported official evidence deletes the un-evidenced POTUS term and score rows so US0 has zero current terms, preserving the person and identifiers.

### Evidenced presidential term and seat are preserved when official evidence is supported

Seeding with supported official evidence retains the evidenced presidential term and seat identity rather than retiring them.
