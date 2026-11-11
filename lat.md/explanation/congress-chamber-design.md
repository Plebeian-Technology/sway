---
lat:
  mode: explanation
---

# Why CongressChamber is built this way

`CongressChamber` answers what a chamber of Congress says about the person sitting in it: how they are addressed, and how many years one of their terms runs.

It is held in one place because two callers ask the same question and would otherwise drift apart — the seeder reads a chamber off each roster entry, and the term-length repair reads one off the same file to fix terms that were stored as two years for everybody, senators included.

## Why WHITE_HOUSE is its own constant

`WHITE_HOUSE` is what the roster writes in the President's `"chamber"` field.

It is not a chamber of Congress at all, and reading it as one makes the President a representative — which is what this constant exists to catch.

## Why title_for takes two signals for the President

`.title_for` needs two ways to know the President, because neither is enough on its own.

A caller reading Sway's own roster knows from the `POTUS` marker and says so via the `president:` keyword. A caller reading the file straight through has only the chamber field, and that one says `"White House"`.

## Why an unrecognized title defaults to Representative

`.term_years_for` treats anything unrecognized as a seat in the House. That is the shorter of the two chamber lengths, so a title nobody expected shortens a term rather than keeping somebody in office who has actually left.
