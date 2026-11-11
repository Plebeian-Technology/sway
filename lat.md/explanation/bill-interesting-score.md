---
lat:
  mode: explanation
---

# The bill interesting score

`BillInterestingScore` records how much disagreement a bill carries, so the Bill Creator's picker can order candidates by it. Rows are only added, and the newest row for a bill is the only one any reader takes.

`BillInterestingScoreCalculator` derives the number from five signals across jurisdictions: how many
legislators voted against their own party, what share of the chamber abstained,
how far the organization positions on the bill are split, how actively citizens
submitted hearing testimony, and how recently the bill moved. Two places read the
result. `Bill#latest_bill_interesting_score` is a `has_one` ordered by descending id,
and `BillCreator::PickerBillsSerializer` carries its own subquery ending `ORDER BY s.id DESC LIMIT 1`.
Neither looks at a second row, and no surface shows a history of the score.

## Why a bill gains a row every day

The table grows by one row per bill per day. That rate follows from the daily legislator-vote sweep rather than from anything in the score itself.

`LegislatorVoteSweepJob` runs at 09:00 UTC and enqueues a
`LegislatorVoteFetchJob` for each bill. That job writes each bill's votes again
whether or not the upstream answer changed.
`LegislatorVote#enqueue_interesting_score_recompute` runs after every commit and
enqueues `RecomputeBillInterestingScoreJob`, and `BillInterestingScoreCalculator#call`
inserts a row on every call rather than updating the previous one.

Every recompute reaches the calculator through that after-commit hook. No entry
in `config/recurring.yml` recomputes the score on a timer;
`bill_interesting_score_retention`, which prunes rows, is the only
interesting-score entry there.

The growth is therefore driven by the schedule, not by events in the data. An
append that followed a genuine change in a bill's votes would leave a handful of
rows over the bill's whole life; an append that follows a daily re-save leaves
one a day for as long as the bill exists, so the table gains roughly one row per
bill per day.

## Why retention keeps the newest row for each bill

`BillInterestingScoreRetentionJob` deletes rows older than thirty days, except the newest row for each bill, which is kept whatever its age.

An age cutoff on its own would leave a bill with no score at all once its votes
had not been written for thirty days — a bill in a locale the sweep does not
reach, or one whose fetch keeps failing. The picker would then show nothing for
the least active bills, which is the opposite of what a retention sweep is for.
Being superseded rather than being old is what makes a row unreadable, so the
delete tests both conditions.

"Newest" means the highest id rather than the latest timestamp, matching the two
readers above, so the exclusion is written as `id NOT IN (SELECT MAX(id) FROM
bill_interesting_scores GROUP BY bill_id)`. The table's index on
`(bill_id, id)` covers that grouping; the reasoning for column order is in
[[query-plan-indexes]].

Nothing is lost to a later recompute. `BillInterestingScoreCalculator` reads
legislator votes and organization positions, never an earlier score row, so a
pruned history has no effect on the next value it produces.

### Why the delete runs in batches

Ids are collected a thousand at a time and deleted by id, rather than in one statement covering the whole aged set.

These rows live in the primary database, and SQLite admits one writer at a time
([[auxiliary-databases]]). A single delete over several thousand rows holds that
writer for the length of the statement, and a vote arriving in that interval is
blocked until it finishes. A bounded batch bounds the interval.

The loop ends when a pass collects fewer ids than the batch size. It terminates
because the newest row for a bill is never in the collected set, so the set the
next pass sees is strictly smaller than the one before it.

## Signals follow published evidence

publishes_legislator_votes selects the signal set and its fixed ceiling. The calculator and picker share theoretical_max so read-time scores use the same scale as stored scores.

Only real votes contribute defection and abstention signals; inferred votes do
not. In Congress and Maryland (`publishes_legislator_votes: true`), the two vote signals
(40 defection + 10 abstention) contribute up to 50 points of deliberation. In Baltimore
(`publishes_legislator_votes: false`), individual roll calls are not published. Instead,
constituent hearing testimony (`WEIGHT_TESTIMONY_ENGAGEMENT = 50.0`) replaces absent
roll-call votes, bringing Baltimore's ceiling to the same 100.0 maximum.

Testimony engagement is derived from `bill_llm_provisionings.cleaned_testimony["counts"]`,
with fallback to approved `campaigns` records when the pipeline artifact is absent.
Constituent comment volume discounts automated form-campaign repetition
(`TESTIMONY_REPEAT_DISCOUNT = 0.20`) and awards distinct campaign groups:
`effective_volume = individual_letters + (campaign_origin_letters * 0.20) + (group_count * 2.0)`.
Volume scales linearly up to `TESTIMONY_VOLUME_CAP = 50.0`, saturating at 50.0 points.
When testimony data is absent, the signal degrades honestly to 0.0 without faked engagement.
Federal and state bills set testimony engagement to 0.0.

Organization positions pass through normalize_support before counting. The
member-facing flow stores support and oppose as well as FOR and AGAINST; exact
matching would silently omit valid positions. Normalizing the read preserves
the existing stored wording and edit history.

The stored timeliness signal is a snapshot at computation. It fades linearly
from the latest introduced or final chamber-vote date to zero after the configured
window. The picker recomputes that signal when read so aging needs no new row.

## Picker reads

The picker reads its displayed columns and indexed vote and position counts in one query. Loading each bill's full serialization would repeatedly load votes during five-second admin refreshes.

Arel qualifies columns shared by bills and joined legislators. The latest score
uses descending id, matching the model reader; a Ruby computed_at timestamp
precedes insertion and cannot decide insertion order. Locale rules and the score
ceiling are read once before mapping rows.

Unknown jurisdiction rules, missing score rows and corrupt signals JSON yield
no score or badges. A read remains available for repair while the calculator
refuses writes with unknown rules. Rebuilt scores clamp to zero through one so
a stale row from a different locale cannot exceed the declared ceiling.

Badges follow controversial, close, live order. The close badge requires
published legislator votes; Baltimore's pass/fail outcomes provide no margin.


## Why picker sort controls grow on phones

The A-Z and Most Interesting buttons have a 44px minimum height and width below the medium breakpoint. Small text alone leaves their touch targets too small for phone use.

Desktop keeps the compact segmented control. The existing wrapping caption row accommodates the wider targets on narrow screens. The control has no drop shadow so the bill picker remains the main visual element.

The browser spec covers sorting, signal badges, and rendered target sizes. Component tests cannot measure CSS layout. Scoring mathematics, recompute jobs, and jurisdiction-specific badge exclusions remain covered by service, job, and request specs.


## Why picker selection targets grow on phones

The locale trigger, locale options, bill search field, and bill options have a 44px minimum height below the medium breakpoint. Compact desktop controls keep their existing sizes.

The picker passes responsive classes to its combobox popup. Its locale selector sizes its own trigger and options. These local overrides leave other select and combobox users unchanged. The minimum also covers the short New Bill or All Bills row, which otherwise has a smaller target than a bill with metadata.

## Why the picker keeps search and navigation separate

The shared bill picker displays choices for every creator tab. The shell owns navigation and unsaved-change warnings, so the picker reports selections without navigating.

The shared sentinel means New Bill on the creator, scheduler, and summary tabs, and All Bills on the pipeline tab. It stays first during filtering. A searchable combobox remains usable when a jurisdiction has hundreds of bills.

The closed trigger uses a short title. Search keywords include the full stored title, bill number, sponsor, status, chamber, and category. Baltimore titles often place the subject after the shortened portion, so label-only search would hide matching bills.

Sort mode lives in React state and resets to Newest on reload. The raw score travels with each option for sorting but never appears as a number. Score ties fall back to comparing lowercase labels. Unscored bills use a score of -1 so they follow scored bills without random ordering.

The caption is a plain span linked through aria-labelledby. A Radix Label would interfere with copying its text and open the picker on click. The caption row wraps to avoid page overflow. The trigger uses bg-muted because some themes give bg-input and bg-card the same color.

## Why locale selection stays in the shell

The creator's locale selector offers every admin jurisdiction so an operator can create bills outside their own locale. The shell supplies it as a slot and owns navigation and unsaved-change warnings.

The options come from useAdminSwayLocaleOptions. The server accepts sway_locale_id and remembers the choice in a cookie. The selector displays pendingSwayLocaleId before the confirmed locale while navigation runs, so the visible choice does not snap back to the previous jurisdiction.

The picker browser example selects the option whose label belongs to its bill fixture's locale. Choosing the first option could change the locale because the selector lists every admin jurisdiction.
