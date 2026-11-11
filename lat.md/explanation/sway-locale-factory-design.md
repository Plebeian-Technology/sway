---
lat:
  mode: explanation
---

# sway_locale factory design

`spec/factories/sway_locales.rb` (`FactoryBot.define`, factory `:sway_locale`) has three interlocking rules that are easy to break by editing it in isolation.

`spec/factories/sway_locales.rb` (`FactoryBot.define`, factory `:sway_locale`) has three interlocking rules that are easy to break by editing it in isolation: what jurisdiction a bare `create(:sway_locale)` gets, how concurrent creates for the same jurisdiction are made safe, and what happens when two callers ask for the same place.

## Naming a jurisdiction in full, or naming none of it

Sway can only answer a question about a jurisdiction whose term rules it declares — when its terms begin, how long they run (see `SwayLocale::TermRulesRegistry`, the wider design is in [[docs/explanation/jurisdiction-rules-design.md|Why JurisdictionRules exists, and how it is organized]]).

A made-up city has no calendar, so seating a legislator there and then asking whether they hold office raises instead of quietly borrowing another jurisdiction's dates.

The factory used to hand out a random Faker city, which meant most of the suite ran against jurisdictions that cannot exist. The default now rotates through the locales Sway really seeds, read from the same file the seeder itself reads (`db/seeds/data/locales.json`), so the two cannot drift apart. Consecutive bare creates still hand back different locales, which is what the random city was for. A spec that needs a particular jurisdiction has to name it.

`city`, `state` and `country` are transient and default to `nil`, so the factory can tell "the caller said nothing" from "the caller said part of it." The rotation only fills in the first case. It used to fill in each field on its own, so naming one and leaving the rest built a jurisdiction the caller never asked for:

```ruby
create(:sway_locale, state: "MD")   # -> congress-maryland-united_states
```

No such place exists. It is in neither registry, so `LegislatorTerm.current` filters it out with a warning, every legislator in it reads as not serving, and a lookup that should find one comes back empty. That is what broke `sway_registration_open_states_spec` — and it only broke in a full run, once enough earlier specs had moved the rotation, naming whichever spec happened to be standing there. Adding examples anywhere could tip over another.

**The rule: name a jurisdiction in full (`city:`, `state:`, `country:`), or name none of it.** `initialize_with` raises an `ArgumentError` if a caller names one or two of the three fields but not all three, with a message pointing at the traits below.

A second, different jurisdiction has to be named explicitly too. Two bare creates land on two rotation positions, but a bare create can still land on a locale the spec already holds by name — that is how `fetch_bills_service_spec` got Baltimore twice and hit the unique index. The factory cannot know which places a spec is already using, so a spec that needs a particular one, or two it can tell apart, says so:

```ruby
create(:sway_locale, :baltimore)
create(:sway_locale, :maryland)
```

The three jurisdictions Sway really seeds are available as traits: `:baltimore`, `:maryland`, `:congress`.

## Concurrent creates: a mutex and bounded retry

`(city, state, country)` is UNIQUE in the schema, and system specs create `sway_locale`s from two threads at once.

`(city, state, country)` is UNIQUE in the schema, and system specs create `sway_locale`s from two threads at once: the RSpec main thread, and the Capybara Puma server thread running controller code that calls `SwayLocale.find_or_create_by_normalized!`. Either one can insert a row with the same city, state and country. `find_or_create_by!` does a SELECT and then an INSERT, which is a race between two connections, and SQLite's WAL (write-ahead log) means one connection cannot always read straight away what the other just wrote — so the race shows up either as a uniqueness error or as a `RecordNotFound` further along.

A mutex shared inside the process takes create attempts one at a time, and a bounded retry soaks up whatever still slips through, which keeps the factory predictable.

## Normalization and reuse: a locale belongs to whoever made it first

The factory's lookup has to use the same form the row is stored in.

`SwayLocale` normalizes `city`, `state` and `country` before it saves ("MD" becomes "maryland"), so searching on the raw values never found an existing row — the create then hit the unique index instead. That stayed hidden while every spec invented its own city; it shows up as soon as two specs name the same place two different ways.

A locale that already exists belongs to whoever made it. FactoryBot writes this factory's own attributes onto whatever `initialize_with` returns, so a second create for the same place used to overwrite the first one's values — a spec would set a session start date, and the next association that happened to want the same locale would quietly put the default back. Nothing noticed while every locale was invented fresh. `to_create` now saves a genuinely new record but reloads (rather than re-saving) one that already exists, so a second caller reads the first caller's values instead of clobbering them.

## Why the district factory looks up before creating

`(name, sway_locale_id)` is UNIQUE on `districts`.

`spec/factories/districts.rb`'s `:district` factory used to be safe from that by accident: the old `sway_locale` factory invented a new city every time, so two bare districts never shared a locale. Now that locales are the real ones Sway seeds (see above), two bare districts DO land in the same locale, and the second insert used to fail on the unique index.

`initialize_with { District.find_by(name:, sway_locale:) || new({name:, sway_locale:}) }` hands back the existing row instead. That keeps the seat at number 0 — the at-large seat, which `SwayLocale#at_large_district` looks for and controller code relies on. A spec that wants two different seats in the same locale has to name them explicitly.

## Why the address factory hardcodes a real city

`spec/factories/addresses.rb`'s `:address` factory sets `city { "Baltimore" }` and `region_code { "MD" }` rather than a Faker city.

`spec/factories/addresses.rb`'s `:address` factory sets `city { "Baltimore" }` and `region_code { "MD" }` rather than a Faker city, for the same reason the `sway_locale` factory above rotates real seeded jurisdictions rather than inventing one: registering an address creates a `SwayLocale` row for its city and its state (`Address#sway_locales`), and the shared "Setup" context then seats a legislator there. Sway can only say when a term runs in a jurisdiction whose rules it declares, so an invented city produces a legislator nobody can answer a question about. Baltimore is Sway's home locale and the natural stand-in; a spec that needs somewhere else should name it.
