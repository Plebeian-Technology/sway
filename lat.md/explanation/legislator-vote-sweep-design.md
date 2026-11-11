---
lat:
  mode: explanation
---

# Why LegislatorVoteSweepJob filters, paces, and skips the way it does

`LegislatorVoteSweepJob` runs once daily (9am UTC / 4am EST) and enqueues one `LegislatorVoteFetchJob` per `Bill` across every `SwayLocale`, but only after filtering out bills that can't possibly produce a useful fetch.

## The pre-vote bill filter

A bill with no vote to look up yet just wastes a request, so the sweep filters per jurisdiction's `vote_source` before enqueuing:

- **Congress + Maryland** (`:congress_dot_gov`, `:open_states`): require a
  `Vote` with at least one house or senate roll-call number. Congress.gov
  and Open States are asked for a roll call *by number*, so a bill with no
  roll-call number on any of its votes has nothing to fetch yet. `Bill`
  declares `has_many :votes` (plural), and the filter joins on that
  association with `.distinct` to avoid duplicate `Bill` rows when a bill
  has more than one `Vote`.
- **Baltimore** (`:legistar`): require `external_id` present. Legistar is
  asked for a matter by its file number, which Sway stores as the bill's
  `external_id`; a pre-vote Baltimore bill has no Legistar pointer yet.

This filter used to require `external_version` instead — an optional, hand-typed admin form field that pipeline-seeded bills never carry. `external_id` is the `MatterFile` pointer that `BaltimoreLegislatorVoteUpdateService` actually resolves the `matter_id` from at run time, and it is present on every Baltimore bill. Gating on `external_version` silently skipped every pipeline-seeded bill.

A jurisdiction declared in the registry with no filter branch written for it here raises `ArgumentError` rather than guessing — guessing risks sweeping the wrong bills.

Sponsor inference for pre-vote bills happens separately, via the create/update triggers (`Vote#after_create` + `Bill#after_commit` on whitelisted fields), not through this sweep.

## Enqueue pacing

The sweep spaces enqueues 0.5s apart (`~120 jobs/min`) so it doesn't dump its whole queue depth at 9am UTC and trip Legistar / Congress.gov / Open States rate limits.

The sweep spaces enqueues 0.5s apart (`~120 jobs/min`) so it doesn't dump its whole queue depth at 9am UTC and trip Legistar / Congress.gov / Open States rate limits — well under any sane upstream throughput cap, and still finishes inside the 9am→noon UTC window for current locale sizes. `on_conflict: :discard` on the fetch job still dedupes a duplicate enqueue if `Vote#after_create` fires around the same time.

The per-bill wait is capped at `WAIT_CEILING_SECONDS` (1800s = 30 min) so the tail can't drift into the next sweep's window once a locale passes ~3,600 bills (1800s / 0.5s = 3600). Past the cap, every remaining enqueue fires at the ceiling — still rate-limited by the same per-bill `on_conflict: :discard` guard on the fetch job.

## The settled-bill skip

A bill whose newest chamber vote happened in a past year, and which already holds at least one real (non-inferred) recorded row, has nothing left to learn — the roll call is settled and recorded (`settled?`).

Re-fetching it daily anyway is what wrote a 2026 roll call onto a 2024 bill for weeks: roll-call numbering restarts each year, so an old bill's number eventually names a fresh, unrelated vote.

The non-inferred test is the deliberate half of the rule. A bill holding only sponsor-guess rows hasn't recorded its roll call yet, so it keeps being fetched — that's also how the wrong-year cleanup migration gets the bills it wiped re-fetched exactly once, with the right year. Bills voted *this* year keep being swept too, so late corrections still arrive.

Only the sweep skips a settled bill. A fetch triggered by an admin edit (`Vote#after_create`, `Bill#after_commit`) still runs unconditionally.

## Why force_refresh: is accepted but does nothing

Per-bill writes are gated by source policy in the underlying services (manually entered rows are never overwritten); `LegislatorVoteFetchJob`'s `on_conflict: :discard` drops duplicate enqueues from an overlapping sweep.

`force_refresh:` is accepted as a retained no-op — the kwarg it used to forward went with the deleted Python sidecar — so a deploy never breaks a job already serialized in the queue.

## Why Vote.after_create hands the fetch to a background job

`Vote#create_legislator_votes` (the `after_create` callback) enqueues `LegislatorVoteFetchJob` rather than fetching legislator votes inline during the save.

The job itself decides which source to query — Congress, OpenStates, or Baltimore's Legistar — by asking the bill's `SwayLocale` what kind of locale it is; nothing at the enqueue site matches on a city name to make that choice. Backgrounding the fetch keeps `Vote.create!` from blocking on a slow outside website during an admin's save, and keeps that outside service's errors from surfacing as a failure of the admin action that merely recorded a roll-call vote number.

## Why the perform prefilter spec drives the query instead of grepping source

An earlier version of `spec/jobs/legislator_vote_sweep_job_spec.rb` checked the job's source text for the literal string `"joins(:votes)"`.

That check broke on harmless refactors while proving nothing about what actually happens at run time. The behavior is covered instead by actually running the prefilter query and asserting it doesn't raise — a singular `joins(:vote)` (the bug this regressed against) raises `ActiveRecord::ConfigurationError` when the query runs, since `Bill` declares `has_many :votes`, plural — together with a `.distinct` de-duplication example.

The `WAIT_CEILING_SECONDS` pacing cap gets the same treatment: an earlier check matched the source text `[i * 0.5, WAIT_CEILING_SECONDS].min` directly, which likewise broke on harmless refactors and proved nothing at run time. The behavioral replacement uses `stub_const` to shrink the ceiling, so 4 bills are enough to observe both the 0.0/0.5s ramp-up and the cap being hit, with no need for thousands of fixtures to reach the real 1800s ceiling.

## What the wrong-year cleanup migration removes, and how the spec pins it

The data migration `20260804000001` wipes every `source='congress'` non-inferred row on a bill holding at least one row created or updated in a later year than the bill's own vote.

The data migration `20260804000001` wipes every `source='congress'` non-inferred row on a bill holding at least one row created or updated in a later year than the bill's own vote — the wrong-year rows the settled-bill skip above exists to stop accumulating further. `spec/production_readiness/production_wrong_year_congress_votes_spec.rb` pins that OUTCOME on an untracked copy of a production database that a maintainer supplies, rather than trusting the migration's own log: no wrong-year row is left, the condemned bills hold no congress-sourced rows, and untouched rows survive to the exact count. On a snapshot taken after the deploy the migration is already recorded, so the example skips itself rather than misreading the fixed fetcher's own later-dated rows.

## Why the not-enqueued assertions pass no trailing anything

`spec/jobs/legislator_vote_sweep_job_spec.rb` asserts that a pre-vote or blank-pointer bill is never enqueued with `expect(LegislatorVoteFetchJob).not_to have_been_enqueued.with(bill.id)` — no trailing `anything` argument.

RSpec's `anything` matcher fills exactly one argument slot (it is not `any_args`), and the sweep enqueues with a single argument. A form like `.with(bill.id, anything)` could never match a one-argument enqueue, so both `not_to` assertions would pass for free even with the prefilter deleted entirely.
