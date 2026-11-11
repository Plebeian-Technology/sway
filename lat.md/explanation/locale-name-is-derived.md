---
lat:
  mode: explanation
---

# A locale's name is derived, not stored

`sway_locales` has no `name` column. `SwayLocale#name` composes one from `city`, `state` and `country` — `"city-region-country"` — every time it is asked, so the name cannot drift from the columns it describes.

Composing is not free. Each of the three parts runs a `RegionUtil` lookup and
then `SwayLocale.format_name`, which strips, downcases, splits and joins; one
call costs about 54 object allocations. That would be unremarkable if the name
were asked once, but it is the key everything else is looked up by —
`TermRulesRegistry`, `JurisdictionRulesRegistry`, `resolve_by_computed_name`,
`human_name` — so it is asked thousands of times per request against three
distinct locales. Memoizing it took one evaluation of
[[current-legislator-term#Why the candidates are bounded in SQL first|the current-term scope]]
from 159,705 allocations to 27,844, with an identical result.

## A shared locale slug is parsed into its name parts

The shared-link slug is split into city, region and country before [[app/models/sway_locale.rb#SwayLocale|SwayLocale]]'s `find_by_name_parts` method reads the matching locale row. The lookup matches those stored parts because a composed name has no database column.

## The picker's options are formatted before they leave the server

Each locale travels to the front end already shaped as the label-and-value pair
the select control wants, through the shared props.

Formatting it server-side means the client never works a display name out
again, so there is one implementation of what a locale is called rather than
two that can disagree. Congress is the special case in both places, and the
server's spelling is written to match the client's own formatter for exactly
that reason. The value is a number, and the component converts the DOM's string
itself rather than passing a string onwards.

## Which attributes the memo is keyed on

The memo remembers `[city, state, country]` alongside the composed name and
recomposes when that triple changes, rather than holding the first answer
forever.

A plain `@name ||=` would be wrong here, and wrong in a way that is easy to miss.
`before_validation :nameify_country, :nameify_region, :nameify_city` rewrites
those three attributes into their normalized form on every save, so a locale
built from a user's raw input answers `name` once before normalization and is
then expected to answer differently after it. Registering a user creates a
locale row for their own city and state, which is exactly that path.
A locale whose city is reassigned in a console or a migration has the same
shape.

Keying on the attributes rather than clearing the memo from a callback keeps the
invalidation next to the thing being invalidated. A callback would have to be
kept in step with any future attribute the name is composed from; the key
cannot fall out of step, because it is the same list.

## SwayLocale naming conventions across the frontend and mobile

Across the frontend and mobile clients, variables representing SwayLocale data follow four exact naming forms:
- A value that holds a SwayLocale's raw slug is named `swayLocaleSlug`.
- A value that holds text shown to a reader is named `formattedSwayLocaleName`.
- A value that holds the record itself is named `swayLocale`.
- A value that holds its numeric primary key is named `swayLocaleId`.

## Client-side bootstrap locale type narrowing

Bootstrap locale data in mobile screens is typed generically on the payload interface and narrowed at the component boundary.

`Bootstrap.locale` arrives as `Record<string, unknown>`. Screens like `BillOfTheMonthScreen` narrow this value to `{ id: number; name: string }` matching `SwayLocalePickerSheet` expectations, as the runtime fields are guaranteed by server serialization.

## Mobile SwayLocalePickerSheet edge margin toggle

The mobile picker sheet trigger adapts its margins depending on whether the containing screen already provides horizontal padding.

On screens with outer horizontal padding like the featured bill screen, `withHoriztonalMargin={false}` lets the trigger stretch edge-to-edge across the padded column. On list screens without outer horizontal padding, the default value `true` retains standard screen margins.

## Mobile test formatting fixtures

Test fixtures in the mobile suite provide lowercase hyphenated slugs to verify client-side formatting.

`toFormattedLocaleName` transforms slugs like `baltimore-maryland-united_states` into title-cased labels like `Baltimore, Maryland, United States` to confirm the picker sheet displays readable jurisdiction names.

## Frontend SwayLocale constants

The frontend defines canonical SwayLocale constants in `app/frontend/sway_constants/swayLocales.ts`.

The module declares `CONGRESS_SWAY_LOCALE_NAME` for the federal jurisdiction slug, `ESwayLocaleName` enumerating supported jurisdiction slugs, and `VOTING_WEBSITES_BY_SWAY_LOCALE` mapping each slug to its legislative portal display label.

## Mobile locale formatting parity

Mobile's `Locale` type and formatting helpers match the web's `ISwayLocale` contracts.

The mobile client defines its `Locale` type in [[mobile/src/utils/locale.ts#Locale]] to mirror `sway.ISwayLocale` received from `/api/v1/bootstrap`. Anywhere a slug is shown to a reader, it is run through [[mobile/src/utils/locale.ts#toFormattedLocaleName]] to produce readable jurisdiction text matching the web's `toFormattedLocaleName`, deduplicating repeated hyphen-separated chunks with `Set` and returning `"U.S. Congress"` for `congress-congress-united_states`.

## Why localeLabelFor takes a fallback slug

`localeLabelFor` turns a `sway_locale_id` into the short label shown on screen without country suffix.

The helper accepts the viewer's `locales` alongside the target `swayLocaleId` and an optional `fallbackSlug`. When a signed-in user views an organization outside their own jurisdictions, the id lookup fails against `locales_for_current_user`, and `fallbackSlug` provides the record's own jurisdiction to prevent missing jurisdiction labels on directory cards.
