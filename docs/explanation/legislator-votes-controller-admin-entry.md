---
mode: explanation
summary: "Why LegislatorVotesController shares LegislatorVoteUpserter with the import services, and the reasoning behind its redirect, serialization, and error-handling choices"
status: agent-extracted
related: [docs/explanation/baltimore-legislator-vote-import.md, docs/explanation/bill-creator-redirect-query-params.md]
---

# `LegislatorVotesController`: manual admin vote entry

## Shared upsert path

`LegislatorVotesController` includes `LegislatorVoteUpserter`, the same
shared way to save a legislator's vote used by the three data-import
services (Baltimore, Congress, OpenStates), so a later change to
`LegislatorVoteUpserter` cannot apply on one path and not the other. The
admin path passes `source: "manual"`, which means an admin's entry beats an
imported one when the two disagree.

## Why `#create` always redirects to the Creator tab

The Legislator Votes panel appears only on the Bill Creator's Creator tab,
never on the Summary tab. So `#create` always redirects to
`creator_bill_creator_path`, leaving the admin on the tab they submitted
from. The bill id travels inside that path.

## `#index` serializes through `LegislatorResource`

Dumping the records straight to JSON would send every legislator column,
including `last_seeded_at`, the term columns, and the timestamps.
`LegislatorResource` matches `Legislator#to_builder`, the shape every other
legislator payload uses.

## `#show` skips the sign-in check

How a legislator voted is public and is not narrowed to one locale, the same
as `BillsController#show`, which likewise skips the sign-in check.

## `#create`'s guard against a nil vote list

`#create` returns early when `legislator_votes_params[:legislator_votes]` is
blank. Without that guard, the loop below calls `.each` on `nil` and crashes
into the catch-all rescue at the bottom.

## Collecting failures instead of committing partial rows

`LegislatorVoteUpserter` never raises on a bad row: it swallows the
validation and uniqueness errors and returns false. Without collecting those
failures, the good rows would commit — firing their score-update jobs —
while the batch still reported success. `#create` collects the failures and
rolls everything back in the same transaction, so a half-saved batch never
lands.

## Why `saved` and `event_key` go through the path helper

See `docs/explanation/bill-creator-redirect-query-params.md` — this
controller's `#create` follows the same convention as the rest of Bill
Creator.

## Why the rescue passes `e.message`, not the exception

The catch-all rescue passes `e.message`, a plain String, never the exception
object itself. The object turns into nothing the client can use once it is
serialized into the `errors` prop.
