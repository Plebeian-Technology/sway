---
lat:
  mode: explanation
---

# BillCreator::PickerBillsSerializer

Builds the short list of bills the Bill Creator shows in its picker: the combobox in the left column, the Pipeline tab's "Limit to bill" filter, and the Schedule tab. It is the `bills` prop on `#new` and in `bill_creator_props`.

## Why it skips Bill.to_builder

`Bill#to_builder` loads every vote for every bill.

`PickerBillsSerializer` instead reads only the columns these three surfaces display. Each row carries more than `{id, external_id, title}` — status, chamber, category, sponsor, introduced date, a legislator-vote count, and an active-position count — as two subqueries in the same statement, so the whole list costs one database trip. Both `bill_id` columns are indexed, which matters because the admin screen refetches this prop every 5 seconds.

## Why every column goes through Arel

Every bill column is named through Arel rather than a bare symbol, because the joined `legislators` table also has `title`, `external_id`, and `active` columns, and the database would not know which one was meant.

## Why the score subquery sorts by id, not computed_at

The newest-score subquery sorts by id, not `computed_at`.

The newest-score subquery sorts by id, not `computed_at`: SQLite assigns ids in commit order even when multiple jobs recompute concurrently, while `computed_at` is stamped by Ruby (`Time.current`) before the insert commits, so two rows written in the same second could sort wrong.

## Why jurisdiction rules are read once, up front

`scope` is always a `Bill` query already narrowed to one locale — both `#new` and `bill_creator_props` pass `Bill.current_session(current_sway_locale)`.

`locale` is that same locale. The parts of the interesting-score math that depend on the locale are worked out once here, up front, so the `.map` block never has to touch the database.

Whether a jurisdiction publishes member votes decides which badges can appear and which ceiling the score is divided by; it must match what `BillInterestingScoreCalculator` used when it wrote the row (see [[docs/explanation/bill-interesting-score-design.md|Why BillInterestingScoreCalculator is built this way]] for the write side of this same rule).

This is a READ surface, so an undeclared jurisdiction degrades rather than refuses — the calculator refuses to compute a score on the WRITE side instead. `rules` is nil when no jurisdiction is selected, or the selected one has no declaration. No declaration means no comparable score: the calculator refuses to write one, so any row stored against such a locale predates the declaration and was scaled by rules nobody can name now. It gets the same answer an unreadable row gets: no score, no badges.

## Why a corrupt signals row degrades instead of crashing

The subquery returns raw `signals` text, so Rails never decodes it.

One unreadable row — a console edit, or a future writer that skips JSON encoding — would otherwise crash every Bill Creator page in this locale on each 5-second refresh; it falls back to no badges and no score instead.

## Why timeliness is recomputed live, not read from the stored row

The "how recent" part of the score is computed live, using the same straight-line fade as `BillInterestingScoreCalculator#timeliness_score`.

The "how recent" part of the score is computed live, using the same straight-line fade as `BillInterestingScoreCalculator#timeliness_score` — full weight on day zero, zero after `TIMELINESS_WINDOW_DAYS` — from the date columns `.call` already fetched, so it costs no extra query. This is what lets the `live` badge and its sort weight drop as a bill ages past 30 days between refreshes with nothing recomputed; the stored `BillInterestingScore#signals["timeliness_score"]` is deliberately ignored since it only reflects the value at compute time.

## Why the normalized score is clamped

Rebuilding the score the picker sorts by combines the stored per-signal numbers with the recency term computed live.

It returns nil when the bill has no score row yet, because nothing has ever computed one for it, and the picker sorts those bills to the bottom.

The clamp to `[0, 1]` is belt and braces: a stale score row computed under one locale's jurisdiction rules but divided by another's maximum — after a bill moves between locales — could otherwise exceed 1.0 and outrank honestly scored bills until the recompute lands. Listing `sway_locale_id` in `Bill::SCORE_TRIGGER_FIELDS` closes the known route; the clamp covers the rest.

## Why close never appears for Baltimore

Badges assemble in a fixed order: controversial, then close, then live.

`close` never appears in a city locale, because Baltimore publishes only pass/fail outcomes and no per-member roll call, so there is no real margin to measure. If the bill has no score row yet, it gets no badges at all rather than guessed ones.

## The frontend type mirror (app/frontend/index.d.ts)

`IBillPickerOption` is a trimmed-down bill, used by the Bill Creator picker, the "Limit to bill" filter on the Pipeline and LLM screens, and the Schedule tab.

`BillsController#picker_bills` builds it. It carries more than `{id, external_id, title}` so an operator can tell similar bills apart in the list. The vote and position counts come from indexed subqueries that count inside the same query, so there is no extra database trip per row.

Its `interesting_badges` and `interesting_score_normalized` fields: both are worked out on the server, inside `picker_bills`, as the list is read. `close` never appears for the Baltimore (local) locale. A null score means no score row exists yet, because nothing has been filled in or recomputed — those bills sort last.

## BillPickerRow.test.tsx notes

A row has to show enough — sponsor, status, chamber, dates, vote and position counts — for an operator to tell bills apart and notice the interesting ones.

SIGNAL_BADGE_ORDER fixes drawing order to controversial, close, live, regardless of interesting_badges' order. Baltimore bills can never carry "close".
