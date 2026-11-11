---
mode: explanation
summary: "Why LegislatorVoteUpserter never lets a guessed sponsor vote overwrite a real recorded one, why source and inferred default the way they do, and why every service shares one frozen sponsor-inference vote object."
status: agent-extracted
related: [docs/explanation/baltimore-legislator-vote-import.md, docs/explanation/legislator-vote-record-day-and-verification.md]
---

<!-- vale Vale.Spelling = NO -->

# Why `LegislatorVoteUpserter` guards writes the way it does

`LegislatorVoteUpserter` is the shared "update the row or create it" logic
for the three per-locale vote-import services (Baltimore, Congress,
OpenStates). An admin's hand-entered edit always wins: a row with
`source == "manual"` is never overwritten by a service, any other row is
updated to the new support and source, and a row that doesn't exist yet is
created with the including class's `SERVICE_SOURCE`.

## Why a guessed vote can never overwrite a real recorded one

`#upsert_legislator_vote` refuses to write when the INCOMING row is
`inferred: true` and the EXISTING row is not (`return false if inferred
&& !existing.inferred`). Without this check, the daily
`LegislatorVoteSweepJob` re-running a locale's service against a scraper
that came back empty — a changed page layout, a moved PDF, a blank
upstream page — would silently turn a sponsor's genuine AGAINST vote into
a made-up FOR marked `inferred: true`, wrecking the real-versus-guessed
distinction the interesting-score engine depends on (see
[the bill-interesting-score doc](bill-interesting-score-design.md) for
where that distinction matters downstream).

## Why `source:` and `inferred:` default the way they do

`source:` defaults to `service_source` (read through the including
class's `SERVICE_SOURCE` constant), so the three locale services call
`#upsert_legislator_vote` without passing it. The admin controller passes
`source: "manual"` explicitly to reuse this same write path under admin
rules — a service never overwrites a manual row, and an admin re-saving a
manual row re-stamps it as manual (a no-op if nothing changed).

`inferred:` defaults to `false` the same way, so every call about a real
vote (`upsert_legislator_vote(legislator_id, vote)`) is unaffected. All
three services pass `inferred: true` only from `#infer_from_sponsors`,
which is what keeps made-up sponsor-FOR rows apart from real recorded
votes for the scoring engine.

## Why coming from a service vs. an admin behaves differently on an existing non-manual row

Coming from a service: only rows that are not already manual get
overwritten. Coming from an admin: the source is always re-stamped as
`"manual"`, and the support is updated if it changed — the old admin
controller also flipped the source to `"manual"` when the support was
unchanged but the source was not yet manual, and that behavior is kept
here rather than dropped in the consolidation.

## Why every caller shares one frozen `SPONSOR_INFERENCE_VOTE` object

When a vote is guessed from sponsorship, the answer is always FOR — a made
up row, not a real recorded vote. `SPONSOR_INFERENCE_VOTE` is one shared,
frozen `Struct` instance rather than three separate constants (the three
services used to each keep their own identical copy). Sharing it is safe
because `#upsert_legislator_vote` only ever reads its `#support` and never
mutates it.

## Why `#infer_from_sponsors` records the bill's sponsor and every cosponsor

All three vote-update services carried identical copies of this logic
before it moved here. `bills.legislator_id` cannot be null in the
database, so `@bill.legislator` is always present; the cosponsor list may
be empty. The written rows are marked `inferred: true` so the scoring
engine leaves them out of the party-defection and close-margin numbers.

## Why `service_source` reads `SERVICE_SOURCE` through a method

A class including this module must provide a `SERVICE_SOURCE` constant
("legistar", "congress" or "open_states"). This module reads it through
`service_source` below, so the RBS type signatures never have to know
about a constant on the host class.

## Why only ActiveRecord errors are rescued here

Only two errors are caught here, both about saving one row:
`ActiveRecord::RecordInvalid` and `ActiveRecord::RecordNotUnique`. Network
and upstream errors (`Net::OpenTimeout`, `JSON::ParserError` and the like)
travel up to the job layer (`LegislatorVoteFetchJob`'s `retry_on`) and to
the rake task's circuit breaker.
