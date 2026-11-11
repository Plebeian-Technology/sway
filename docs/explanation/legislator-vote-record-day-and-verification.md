---
mode: explanation
summary: "Why CongressLegislatorVoteUpdateService and OpenStatesLegislatorVoteUpdateService look up the roster on the day the chamber actually voted, verify the roll call actually names the bill before trusting it, and match senators by surname."
status: agent-extracted
related: [docs/explanation/legislator-vote-sweep-design.md, docs/explanation/legislator-vote-fetch-job-design.md, docs/explanation/baltimore-legislator-vote-import.md]
---

<!-- vale Vale.Spelling = NO -->

# Why the Congress and OpenStates vote-update services read the roster and verify the record the way they do

`CongressLegislatorVoteUpdateService` and `OpenStatesLegislatorVoteUpdateService`
share the pattern documented for the Baltimore service — a `SERVICE_SOURCE`
constant, writes through `LegislatorVoteUpserter`, a sponsorship fallback,
no top-level rescue — but each also does its own upstream lookup and
verification that the Baltimore service does not need, because Legistar
never asks Sway to identify a roll call from a year-plus-number pair the
way congress.gov and Open States do.

## Why the year for a roll call comes from the bill's own vote date, never the clock

Both `#senate` and `#house` in `CongressLegislatorVoteUpdateService` ask
for the year the chamber VOTED, taken from the bill's own
`senate_vote_date_time_utc` / `house_vote_date_time_utc` — never from
`Time.current`. Roll-call numbering restarts every year (House) or session
(Senate), so a fetch that pairs an old bill's roll-call number with the
CURRENT year returns a different vote entirely. The daily sweep did
exactly that to every settled bill for weeks — see
[the sweep job doc](legislator-vote-sweep-design.md#the-settled-bill-skip)
for the fix that stops the sweep from re-fetching a settled bill at all. A
roll number with no vote date is skipped and logged rather than guessed;
guessing the year from the clock is what caused the defect in the first
place, so there is deliberately no fallback here.

## Why the roster is read for the day the record states, not the day the bill stores

`#roster_on` (Congress) and `#roster_for` (OpenStates) both build a
`LegislatorRoster` scoped to the day the roll-call RECORD states it was
taken — read from the scraped `identity.voted_on` (Congress) or the bill's
own vote-date column (OpenStates) — not the day the bill stores in a
looser sense, and not "today." `LegislatorRoster` used to default to
whoever is serving RIGHT NOW, so re-fetching an old roll call quietly
dropped everyone who had left office since the vote was taken. Congress's
`#roster_on` treats a record stating no day at all as a hard error
(`Scraper::Congress::RollCallMismatch`) rather than falling back to
today's roster, because the day check earlier in `#verify_record!` has
already refused any record that states no day — reaching `#roster_on`
without one would mean that guard was skipped. OpenStates' `#roster_for`
is more forgiving: with no vote date recorded at all, there is nothing
better to ask than today, so it warns and falls back rather than raising.

## Why `#verify_record!` and `#verify_question!` exist

Congress's scraped roll call carries its own day and its own question
text, independent of what the bill row claims. `#verify_record!` checks
the day the roll call states against the bill's own recorded vote date,
and separately checks the roll call actually asked a question that counts
as a position on the bill (`#verify_question!`) — logging, but not
failing, when the record's own external-id text doesn't name the bill,
since the day and question checks are the load-bearing ones.
`#verify_question!` refuses even a phrase it does not recognize at all,
rather than guessing which side an unfamiliar procedural phrase falls on
— a procedural record (a motion to table, a quorum call) writes NOTHING
rather than assert a position nobody actually took.

## Why senators are matched by surname and state, never the given name

`#senator` matches on `vote.last_name` and `vote.state_code`, deliberately
skipping the given name. Sway stores the formal given name, while the
Senate's own roll-call record prints informal forms — "Maggie" for
"Margaret Wood" — which left about 28 of every 99 senators unmatched on
every roll call when the given name was part of the match.

## Why a shortfall in matched voters is logged by name

`#log_unmatched_voters` (Congress) exists because the shortfall used to be
silent: the written vote count simply came out lower than the published
count, with nothing naming who was missed. Logging the unmatched names is
what turns the next gap into something a person can see the day it
appears, rather than a quietly shrinking number.

## Why OpenStates looks the legislator up through the bill's own locale

`OpenStatesLegislatorVoteUpdateService#legislator_for` looks the
legislator up through the bill's locale-scoped roster, never the global
`Legislator` table directly: two locales can reuse the same
`external_id`, so a global lookup could match the wrong locale's
legislator to a vote row.

## Why sponsor inference is gated on the UPSTREAM count, not the written count

Both `#call` methods run `infer_from_sponsors` only when the upstream
source (congress.gov or Open States) returned zero rows for both
chambers, never merely when zero rows were WRITTEN.
`LegislatorVoteUpserter#upsert_legislator_vote` returns `false` whenever
it leaves an admin's manually-entered row alone (see
[the upserter's own doc](legislator-vote-upserter-guard-rules.md)), so "0
written" can also mean "rows came back from upstream, but an admin had
already edited every one of them by hand." Guessing from sponsorship in
that case would quietly replace the admin's choice with a made-up FOR.
Only falling back when NOTHING came back from upstream at all avoids
that. `CongressLegislatorVoteUpdateService` carries the canonical
explanation of this rule; `OpenStatesLegislatorVoteUpdateService` follows
the same gate and points back here rather than repeating it.

## How `congress_legislator_vote_update_service_spec.rb` fakes the scrapers

Both scrapers are faked for every example, so the `Vote#after_create`
callback — which queues `LegislatorVoteFetchJob`, which runs this service
— never reaches the network. Each test then re-fakes what `process`
returns to shape the data it cares about.

Each fake also answers `#identity` — the service asks the record what it
is before writing. The default agrees; the contexts that care
fake a disagreement.

`"On Passage of the Bill"` is the Senate's own phrasing and also opens the
House family, so one fake serves both chambers. It cannot be left blank:
the service refuses a record whose question is not a vote on the bill.

The fixture states a day for the same reason. `#taken_on?` is false
whenever the record has none, so "the day agrees" and "there is no day" is
a pair no real record can answer — and the day is what the roster is
built from. Both of this bill's chamber votes fall inside one
term, so one day serves both.
