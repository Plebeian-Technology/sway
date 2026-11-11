---
mode: explanation
summary: "Explains the Baltimore vote-import service's shared pattern, why it gates on external_id instead of external_version, and its three-step Legistar algorithm."
status: agent-extracted
related: [docs/reference/legistar-final-passage-action-ids.md]
---
# Baltimore's legislator-vote import

<!-- vale Vale.Spelling = NO -->

`BaltimoreLegislatorVoteUpdateService` is the Baltimore half of a pattern
shared with `CongressLegislatorVoteUpdateService` and
`OpenStatesLegislatorVoteUpdateService`: a `SERVICE_SOURCE` constant, writes
that go through `LegislatorVoteUpserter` (which never overwrites a row an
admin edited by hand), a fallback that guesses votes from sponsorship
(sponsors are recorded as voting FOR), and no top-level rescue — errors
travel up to the job, which is what lets `LegislatorVoteFetchJob.retry_on`
retry them.

## Why the gate is `external_id`, not `external_version`

A bill with no `external_id` has not been voted on yet, and the service does
nothing for it — there is no identifier to look anything up with.

This check used to read `external_version` instead: an optional field an
admin types into a form by hand, which bills created by the pipeline never
have. That silently skipped every pipeline-created bill. `external_id`, the
Legistar `MatterFile` string this service turns into a `matter_id` at run
time (such as `"26-0187"`), cannot be null, is checked for presence, and
exists on every Baltimore bill — so it is what can actually be relied on.

## The three-step algorithm

Baltimore's Legistar records only a pass-or-fail result for a matter as a
whole — a live check of 200 matters turned up no record of how any
individual member voted. The service:

1. **Resolves the numeric Legistar `MatterId` at run time** from
   `bill.external_id` (the hyphenated `MatterFile` string) with a live
   `client.matters(filter:)` lookup. `Bill` has no `matter_id` column, and
   `external_id` is rejected by `Legistar::Client#coerce_id!`, which accepts
   1 to 10 digits only — see `#resolve_matter_id`.
2. **Fetches `client.matter_histories(matter_id)`**, keeps only the rows
   whose action is on the `FINAL_PASSAGE_ACTION_IDS` list, and writes the
   date of the most recent matching row to `bills.house_vote_date_time_utc`.
   Taking the most recent is what handles a veto override, where a matter
   genuinely has two final-vote moments.
3. **Always guesses votes from sponsorship**, before the Legistar lookup, so
   neither a failed `matter_id` lookup nor a network error can stop it. It
   is the only per-legislator information Baltimore offers, and its rows are
   marked `inferred: true`, which `LegislatorVoteUpserter` passes along.

## Why `apply_final_passage_outcome` logs rather than raising on an empty lookup

Works out the `matter_id` when it can, fetches that matter's history, and
writes the most recent final-passage date to `house_vote_date_time_utc`.
When either the lookup or the filtering comes back empty, it does nothing
and logs rather than raising — which is the NORMAL outcome for the vast
majority of daily-sweep runs, since most bills have not changed since the
last one.

## Why `resolve_matter_id` does not read the pipeline's metadata.json

Turns `bill.external_id` (the hyphenated `MatterFile` string, such as
`"26-0187"`) into the numeric Legistar `MatterId`, with a live filtered
lookup. `Bill` has no `matter_id` column, and `external_id` is rejected by
`Legistar::Client#coerce_id!`, which accepts 1 to 10 digits only, so
`external_id` can NEVER be handed to `#matter_histories` as it stands.

It does NOT read `legislation/bills/raw/<external_id>/metadata.json`, the
file on disk `FetchHearingsService` works from. The daily
`LegislatorVoteSweepJob` is not tied to any pipeline run, and that file may
legitimately not be there.

## When a `MatterFile` resolves to nothing

`client.matters` returning `[]` is a quiet no-op on the daily sweep —
`LegislatorVoteSweepJob` runs over all historical Baltimore bills and is not
tied to any pipeline run. It is logged, never a crash, and never an invented
date.

## Other things worth knowing about `BaltimoreLegislatorVoteUpdateService`

The old `force_refresh` keyword the service used to accept is gone. Every
run now asks Legistar directly, so the kwarg — which used to skip a disk
cache — was being set and never read. `LegislatorVoteFetchJob` still
accepts `force_refresh:` from its own callers (the daily sweep and the
rake task) but no longer passes it down here; see
[the fetch job doc](legislator-vote-fetch-job-design.md) for why the job's
own kwarg is kept as a no-op.

`#resolve_matter_id` `.strip`s `bill.external_id` before checking it
against `MATTER_FILE_PATTERN`, as a precaution: an identifier with stray
spaces around it — `"25-0187 "` from an import that predates stripping, or
a value an admin typed by hand — should still resolve instead of failing
the shape check on every sweep forever. `FetchBillsService` strips on
import too; this covers rows written before that or through some other
path.

`#write_final_passage_date` treats two failure modes as skip-and-log
rather than crash. An unparseable `MatterHistoryActionDate` (`Time.zone.parse`
raising `ArgumentError` on a string like `"99-99-99"`) is logged and
skipped — dirty upstream Legistar data, not a reason to crash the sweep.
An `ActiveRecord::RecordInvalid` on the bill save is also logged and
skipped rather than allowed to propagate: two Baltimore bills reached
production with an empty `status`, which the model's presence check
refuses, so saving ANY column on them failed — and this job, which only
wants to set a vote date, was the thing that raised every day.
Catching it here does NOT let the bad value through — the save still
refuses and the vote date still goes unwritten — but a row nobody can save
no longer takes the whole run down, and the log names the column actually
at fault instead of leaving a reader to work out why setting a date
produced a complaint about status.

`#latest_final_passage_row` settles same-day ties on `MatterHistoryId` so
the answer is deterministic — Legistar's history rows are not guaranteed
to arrive in date order, and picking the most recent action date alone
would leave a same-day tie unresolved.

`#legistar` builds its client from `@bill.sway_locale.jurisdiction_rules.legistar_client!`
rather than the client's default jurisdiction, for the same one-instance-
per-city reason `JurisdictionRules` exists at all — see
[the JurisdictionRules doc](jurisdiction-rules-design.md).
