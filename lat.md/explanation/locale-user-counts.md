---
lat:
  mode: explanation
---

# How many people have registered in each locale

The admin locales page shows every `SwayLocale` with the number of registered users behind it. One user counts toward three rows — their city, their state, and Congress — because that is how many locales an address resolves to.

Sway creates a locale row for any registration address
([[locale-name-is-derived]] covers how that row is named), so this page is the
admin's view of where sign-ups actually land, including jurisdictions nobody
chose to support. The general nav selector no longer shows those.

## Why the count matches against existing locale rows

`SwayLocaleUserCountsService.by_sway_locale_id` returns user counts keyed by SwayLocale ID. It resolves addresses through
[[app/services/sway_locale_user_counts_service.rb#SwayLocaleUserCountsService#sway_locale_for_address]] and [[app/models/sway_locale.rb#SwayLocale|SwayLocale]]'s attribute normalization, never through
`Address#sway_locales`.

The difference is that `#sway_locales` is `find_or_create`. It exists for
registration, where a locale the system has not seen before should come into
being. This runs behind an admin page load, where it must not: a page that
reports how many locales exist cannot be the thing that invents one.

## Why only the distinct address components are read

The service asks the database for the distinct city, region code and country
triples that registered addresses use, and does its Ruby matching once per
triple rather than once per user.

Only those three components decide which locales an address belongs to — the
street never enters into it — so every registration in Baltimore produces the
same answer. Walking one row per user recomputes that answer once per user to fill a
handful of hash entries, and the cost grows with every signup while the answer
stays a few numbers. The number of distinct triples is bounded by geography
rather than by growth.

The matching itself stays in Ruby. Pushing it into SQL would mean spelling
`SwayLocale.format_name` out a second time in a query, and the two spellings
would not agree: `format_name` splits on a single space, which is Ruby's
awk-style split and collapses runs of whitespace, where a `REPLACE(city, ' ',
'_')` would preserve them. A city entered as `New  York` would match under one
rule and not the other. Grouping first makes the Ruby cheap enough that there is
nothing to gain by risking that.

## Why the count is asked locale by locale

Once the triples are matched, each locale is counted with its own
`COUNT(DISTINCT user_id)` over the addresses whose components reached it,
rather than by summing a per-triple count.

Summing per triple counts address rows; the column counts people. Several
triples reach one locale — Baltimore and Annapolis both reach Maryland and
Congress — so a sum is right only for as long as no person appears under two of
them. `COUNT(DISTINCT user_id)` answers the question the column name asks
without depending on that, including on the one-address-per-user rule
[[identity-and-access#A user holds one address]] keeps in the schema.

Walking users had the same flaw in a different place. The join produced one row
per `user_addresses` row while `User#address` is a `has_one`, so the extra rows
were each counted against whichever single address the association happened to
return. The count could therefore exceed the number of accounts whenever one
account held more than one address in a locale.

This costs one small count query per locale that has users, on a page whose
whole purpose is to list those locales. None of it reads a row per user.

## Why the attribute sets are reachable without a record

`Address.sway_locale_attribute_sets_for` takes the three components as keywords
and the instance method passes its own columns to it.

The count has component triples, not addresses, and building a throwaway
`Address` to ask each one which locales it belongs to would be instantiating a
record to reach a rule that never depended on having one. Splitting the rule out
keeps a single definition of what the three sets are, shared by registration —
which has a record — and by the count, which does not.

The Congress set always names the United States, whatever country the address
carries, so every address counts towards Congress
([[representative-resolution#Congress fallback]]).
