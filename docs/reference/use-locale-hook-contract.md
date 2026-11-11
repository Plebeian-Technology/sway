---
mode: reference
summary: "Parameter and return contract for the useLocale hook, including why the locale value is optional."
status: agent-extracted
related: []
---

# useLocale hook contract

`useLocale` (`app/frontend/hooks/useLocales.ts`) returns
`[locale, getLocale, pendingLocaleId]`.

## `refreshProps` parameter

Pass a module-level constant, not an inline array literal. An inline array
literal gets a new identity on every render, which would make the returned
`getLocale` callback unstable.

## Return value

Render a locale picker's value as `pendingLocaleId ?? locale?.id` (see
`docs/explanation/legislators-history-per-locale-state.md` and
`docs/explanation/locale-picker-pending-id-optimistic-ui.md` for why the
active locale alone is not enough).

`locale` is optional. It comes from `props.sway_locale`, which the server's
shared-props block builds as `current_sway_locale&.to_sway_json`, and which
is missing on any page rendered outside the normal shared-props pipeline
(tests, error pages).

Every call site already handled this as `locale?.id`, but the return type
used to claim `locale` was never optional — so four call sites that read
`locale.name` or `locale.id` directly (without `?.`) had no type error
warning them, and would have crashed at runtime on such a page.

## `swayLocaleId` in the Bill Creator form

`useBillFormSubmit`'s `swayLocaleId` parameter is optional because
`props.sway_locale` is optional: it is missing on any page rendered outside
the usual shared-props path. A bill belongs to exactly one jurisdiction, so
the save refuses rather than posting without one.

`useNewBillInitialValues` sets the form's initial `sway_locale_id` to
`locale?.id ?? bill?.sway_locale_id`. `props.sway_locale` being missing
outside the shared-props path is the same reason it is optional there too.
These are only the INITIAL values, so falling back to the bill's own
jurisdiction is the right move, better than inventing an id. The saving
code trusts neither of them: `useBillFormSubmit` refuses to save with no
jurisdiction.

`IApiBillCreator["sway_locale_id"]` is typed `number | undefined` rather
than `number`, for the same reason: undefined is reachable, since
`props.sway_locale` is missing outside the shared-props path and a bill
carries no jurisdiction of its own to fall back on there.
