---
lat:
  mode: explanation
---

# Why SeedCategory doesn't use Seedable

`SeedCategory` does not include `Seedable` because categories have no `last_seeded_at` column.

The slug is the stable key instead: `find_or_create_by!(slug:)` means a re-run never duplicates a category and never overwrites a display name someone changed by hand.

## Why the slug is read-only on the record

`Category#slug` is set once at creation (`Category.slugify`) and never changes — a rename touches `:name` only, keeping `bill_categories` links and `SeedCategory`'s `find_or_create_by!(slug:)` stable.

`attr_readonly` on the `Category` model enforces this on the record itself, so a console session or an import script can't change the slug either, not only the ordinary write paths.

## Why the normalized-slug check only runs on create

`Category#slug_is_normalized` (`validate :slug_is_normalized, on: :create`) only runs when a category is created, since a slug is set once and a rename never touches it afterward.

It stops a console session or an import from saving a raw slug like `"Civil Rights"` that the unique index would treat as distinct from `"civil-rights"`.

## Why a collision is validated against at all

`Category#slugified_name_is_unique` exists because `BillCategoryAssigner` looks category rows up by `Category.slugify(name)`, not by name directly.

Two categories whose names slugify to the same key would make one silently hide the other from that lookup, however different their display names look. Checking the slugified form also makes a separate case-insensitive name check unnecessary — "Police" and "police" already collide under it.

## Why slug collisions are checked against active rows only

A category's `#slugified_name_is_unique` validation only compares its name against OTHER ACTIVE categories, even though `Category.find_slug_collision` itself can find an inactive one.

`BillCategoryAssigner`'s lookup is built from active rows only, so an inactive row's slug can't be the one that actually collides at assignment time. Restricting the check to active rows also lets an operator switch off one of two already-clashing legacy rows without the other blocking the save.

## Why slugify transliterates before downcasing

`Category.slugify` runs `ActiveSupport::Inflector.transliterate` before lowercasing and stripping non-alphanumerics.

`Category.slugify` runs `ActiveSupport::Inflector.transliterate` before lowercasing and stripping non-alphanumerics, so an accented name like "Café" folds to "cafe" rather than losing the accented letter outright and becoming "caf". Plain ASCII input passes through the transliteration step unchanged.
