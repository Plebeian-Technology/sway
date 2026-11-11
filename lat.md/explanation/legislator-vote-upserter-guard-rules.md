---
lat:
  mode: explanation
---

# Why LegislatorVoteUpserter guards writes the way it does

`LegislatorVoteUpserter` is the shared "update the row or create it" logic for the three per-locale vote-import services (Baltimore, Congress, OpenStates).

An admin's hand-entered edit always wins: a row with `source == "manual"` is never overwritten by a service, any other row is updated to the new support and source, and a row that doesn't exist yet is created with the including class's `SERVICE_SOURCE`. Every write resolves the covering term through `LegislatorTerm.covering(anchor_date, legislator: leg)` and returns `:skipped` when no term covers the bill's anchor date, rather than falling back to `active_term` or fabricating a placeholder term. `:skipped` is truthy, so a caller deciding whether a write happened compares against `true`; testing the return value for truth counts a skip as a success. Every caller compares that way: `GenericLegislatorVoteUpdateService` and `CongressLegislatorVoteUpdateService` add to `written_count` only on `true`, and `LegislatorVotesController` keeps the skipped legislators in a list of their own.

## What each upsert outcome means for vote coverage

A vote is covered when a term covers the bill's anchor date and this upsert leaves it stored. Coverage counts upsert outcomes, because a legislator can match the roster and still have no vote written.

| Outcome | Meaning | Written | Covered |
| --- | --- | --- | --- |
| `true` | Row created or updated, including an update that changed nothing | yes | yes |
| `:kept_manual` | An admin's row stands and the service left it alone | no | yes |
| `:skipped` | The id finds no `Legislator` row, or no term covers the bill's anchor date, which includes a bill with no anchor date | no | no |
| `false` | The legislator id is nil, the write failed, or the guard refused to overwrite a real vote with a guessed one | no | no |

While a term covers the anchor date, an unchanged re-fetch stays complete because `update!` returns `true` when nothing changed, and an admin's correction stays complete because the vote is stored, even though this run did not write it. The term check runs before the row lookup, so without a covering term a stored row, manual or not, is `:skipped` and reads as not covered, for example after a term or vote date correction. Only sponsor inference can reach the overwrite guard, and that path records no coverage.

On a run that finishes, `matched_count` is the covered count, so the status agrees with the numbers beside it: `complete` when every eligible vote is covered, `partial` when some are, `unresolved` when none are. `GenericLegislatorVoteUpdateService` reports `missing_vote_date` ahead of all three. A row naming no voter still counts as eligible and can never be covered, so it keeps a run from reading complete.

On `fetch_failed`, `GenericLegislatorVoteUpdateService` still reports the covered count. `CongressLegislatorVoteUpdateService` reports its written count, which is assigned only after the loop, so a Congress run that raises part-way reports 0.

`LegislativeVoteCoverage` has a table and a signature but no model class, so `record_vote_coverage` returns early and no coverage row is stored outside specs that stub the constant. The status is computed and then discarded until a model exists.

## Why a guessed vote can never overwrite a real recorded one

`#upsert_legislator_vote` refuses to write when the INCOMING row is `inferred: true` and the EXISTING row is not (`return false if inferred && !existing.inferred`).

Without this check, the daily `LegislatorVoteSweepJob` re-running a locale's service against a scraper that came back empty — a changed page layout, a moved PDF, a blank upstream page — would silently turn a sponsor's genuine AGAINST vote into a made-up FOR marked `inferred: true`, wrecking the real-versus-guessed distinction the interesting-score engine depends on (see [[docs/explanation/bill-interesting-score-design.md|the bill-interesting-score doc]] for where that distinction matters downstream).

## Why source: and inferred: default the way they do

`source:` defaults to `service_source` (read through the including class's `SERVICE_SOURCE` constant), so the three locale services call `#upsert_legislator_vote` without passing it.

The admin controller passes `source: "manual"` explicitly to reuse this same write path under admin rules — a service never overwrites a manual row, and an admin re-saving a manual row re-stamps it as manual (a no-op if nothing changed).

`inferred:` defaults to `false` the same way, so every call about a real vote (`upsert_legislator_vote(legislator_id, vote)`) is unaffected. All three services pass `inferred: true` only from `#infer_from_sponsors`, which is what keeps made-up sponsor-FOR rows apart from real recorded votes for the scoring engine.

## Why coming from a service vs. an admin behaves differently on an existing non-manual row

Coming from a service: only rows that are not already manual get overwritten.

Coming from an admin: the source is always re-stamped as `"manual"`, and the support is updated if it changed — the old admin controller also flipped the source to `"manual"` when the support was unchanged but the source was not yet manual, and that behavior is kept here rather than dropped in the consolidation.

## Why every caller shares one frozen SPONSOR_INFERENCE_VOTE object

When a vote is guessed from sponsorship, the answer is always FOR — a made up row, not a real recorded vote.

`SPONSOR_INFERENCE_VOTE` is one shared, frozen `Struct` instance rather than three separate constants (the three services used to each keep their own identical copy). Sharing it is safe because `#upsert_legislator_vote` only ever reads its `#support` and never mutates it.

## Why infer_from_sponsors records the bill's sponsor and every cosponsor

All three vote-update services carried identical copies of this logic before it moved here.

`bills.legislator_id` cannot be null in the database, so `@bill.legislator` is always present; the cosponsor list may be empty. The written rows are marked `inferred: true` so the scoring engine leaves them out of the party-defection and close-margin numbers.

## Why service_source reads SERVICE_SOURCE through a method

A class including this module must provide a `SERVICE_SOURCE` constant ("legistar", "congress" or "open_states").

This module reads it through `service_source` below, so the RBS type signatures never have to know about a constant on the host class.

## Why only ActiveRecord errors are rescued here

Only two errors are caught here, both about saving one row: `ActiveRecord::RecordInvalid` and `ActiveRecord::RecordNotUnique`.

Network and upstream errors (`Net::OpenTimeout`, `JSON::ParserError` and the like) travel up to the job layer (`LegislatorVoteFetchJob`'s `retry_on`) and to the rake task's circuit breaker.
