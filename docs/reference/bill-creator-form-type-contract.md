---
mode: reference
summary: "Field-by-field rationale for where IApiBillCreator's type deliberately diverges from sway.IApiBill: chamber, summary, scheduled_release_date_utc, and the vote date-time fields."
status: agent-extracted
related: [docs/reference/use-locale-hook-contract.md, docs/explanation/jurisdiction-rules-design.md]
---

# `IApiBillCreator`'s type contract

`IApiBillCreator` (`app/frontend/components/admin/creator/types/index.ts`)
extends `sway.IApiBill` with a handful of fields `Omit`, then re-declares
them with a shape the Bill Creator form actually produces.

## `chamber`

Null until a chamber is chosen — every new bill in a jurisdiction with no
default. Same as `legislator_id`: `useBillFormSubmit`'s `REQUIRED_FIELDS`
check refuses to save on this value. See
[jurisdiction-rules-design.md](../explanation/jurisdiction-rules-design.md)
for why the initial value itself is null rather than a guessed chamber.

## `summary`

Always a string, unlike the wire type: the textarea is seeded with `?? ""`.
`string | undefined` here made the draft reconciler reject a value it can
never receive.

## `sway_locale_id`

See [useLocale hook contract](use-locale-hook-contract.md) for why this is
`number | undefined` rather than `number`.

## `scheduled_release_date_utc`

The Scheduler tab owns this column; the Bill form never sets it
(`inputs.ts`'s `TOmitKeys` lists it beside `id` and `sway_locale_id`).
Required here only because the form was declared to carry it.

## `introduced_date_time_utc`, `withdrawn_date_time_utc`, `house_vote_date_time_utc`, `senate_vote_date_time_utc`

Three reachable shapes, all read by `DateField`: a `Date` from initial
values, an ISO string once picked or drafted through JSON, or `null` when
empty. `sway.IApiBill`'s `string` was never true of the form.
