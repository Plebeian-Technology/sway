---
mode: explanation
summary: "Why BackfillBillInterestingScoresJob has no periodic/cron counterpart, how its unscored-only gate keeps repeat boots cheap, and why it iterates per SwayLocale."
status: agent-extracted
related: [backfill-bill-categories-scope]
---

<!-- vale Vale.Spelling = NO -->

# Why `BackfillBillInterestingScoresJob` is shaped the way it is

`BackfillBillInterestingScoresJob` backfills interesting-bill scores for
every in-scope existing bill, safe to run repeatedly, enqueued at every
boot via `config/initializers/backfill_bill_interesting_scores.rb`.
Modeled on `app/jobs/backfill_bill_categories_job.rb`.

## Why there is no periodic/cron version

This is NOT a recurring job — there is deliberately no periodic/cron
scoring job and no `config/recurring.yml` entry. The "unscored only" gate
(a bill with NO `bill_interesting_scores` row yet) makes repeat boots
cheap: the first boot after the deploy scores every in-scope bill; every
later boot finds zero unscored bills and does zero calculator work.

## Why the scope mirrors the admin picker's own scoping

Scope mirrors the admin picker's own scoping — `Bill.current_session(locale)`
across EVERY `SwayLocale` (Baltimore/Maryland/Congress), the same set of
bills `BillsController#picker_bills` shows admins. `Bill.current_session`
takes a single `sway_locale` (it is called per-locale throughout the
codebase — see `LegislatorVoteSweepJob` — never with a cross-locale union),
so this job iterates `SwayLocale.find_each` and reuses that exact scope
rather than re-deriving the session-boundary condition. A bill outside its
locale's current session (a prior-session bill) is intentionally never
backfilled here — the picker never shows it either.

## Concurrency and pruning

The boot initializer enqueues once; `limits_concurrency` collapses
concurrent puma + `bin/jobs` enqueues into a single run (mirroring
`BackfillBillCategoriesJob`).

No pruning/retention job exists on purpose (growth is bounded by
event-driven recompute, not a periodic sweep) — a low-priority retention
follow-up is tracked as a separate issue rather than built here.

## Why the concurrency key is a fixed proc, not keyed per bill

Only one copy of this job may run at a time. The proc key mirrors the
no-arg form in `backfill_bill_categories_job.rb` (`perform` takes no
arguments, so a `bill_id`-keyed proc — the `RecomputeBillInterestingScoreJob`
pattern — does not apply here).

## Why a bad bill does not abort the batch

One bad bill must never abort the batch (same reasoning as
`BackfillBillCategoriesJob`). A boot-time batch job cannot re-raise for an
ActiveJob retry without dropping every remaining bill this run, so it logs
and continues.
