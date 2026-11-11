---
lat:
  mode: explanation
---

# Why RetireDepartedMembersService exists, and why it is allowed to guess a date

Why RetireDepartedMembersService exists, why the Congress fix does not cover it, and the deliberate exception it takes to the never-fabricate-domain-data rule.

## The problem

OpenStates' `/people` endpoint answers with sitting members and nobody else.

Somebody who leaves simply falls out of the file, the seeder never looks at their row again, and the term they were left with runs to the end of its four-year cycle. Sway decides who is in office by reading when a term ends, so they keep reading as a sitting member — the same defect fixed for Congress, which nothing here reached.

## Why the Congress fix does not reach it

The Congress fix works because a SECOND source publishes whole terms with real end dates, so a stored term can be checked against it.

Maryland has no equivalent. Correcting against a partial list would destroy real rows, which is why `SeedLegislatorTerms` guards correcting and retiring behind `#terms_from_history?`.

## Why a stored term widens to hold a real end date, instead of narrowing

Sway records a term as two YEARS and hands every seat over on the locale's one January (or December) handover date.

A real end date almost never lines up with that, so `CongressTermHistory` widens each stored term to the smallest pair of handover dates that holds it, rather than narrowing the term to the real date. Narrowing would put somebody out of office months before they actually left and drop their votes outside every term they hold, which is worse. The cost of widening is that a person who leaves after the handover date reads as still serving until the NEXT one.

Upstream records the exact day each person left Congress, yet every departure still reads as in office until the next handover date, so a seat can show two people at once and a reader of `/legislators` sees both.

This is not a per-locale rule. The day a term BEGINS is law and differs by jurisdiction (`SwayLocale::TermRules`). A person leaving partway through their term is a fact about the person, not the jurisdiction, and it happens everywhere — so the fix is the `ended_on`/`ended_on_source` column pair added in `db/migrate/20260812130000`: used when present, and the locale's own handover rule when not.

### Why TermWindow.ends_on defaults to the successor's convening date

Absent a real `ended_on`, `TermWindow#ends_on` defaults to the day its successor convenes: a term covers its own convening date up to, but NOT including, this one, so two back-to-back terms are never both running at once.

## What generalizes, and why this is not a Maryland class

Sway learns that somebody left in exactly one way today: a second source publishes their whole past.

That is a property of the SOURCE, not of Congress. The rule written here is therefore the other one: a locale declares whether its roster source lists ONLY people in office now (`SwayLocale::TermRules#roster_lists_only_current_members`). Where it does, absence is evidence, and the day Sway first saw them missing is the best end date available. Where it does not — congress.gov keeps departed members and flags them — absence means nothing and this does not run.

## An exception to never fabricating domain data, granted deliberately

**This service deliberately breaks the "never fabricate domain data" house rule**.

The date it writes is not published by the jurisdiction, and Sway does not pretend it is: the term record's `ended_on_source` is set to `"observed"`, so every reader of that row can tell an observation from a published fact. Anyone touching this file, or the `ended_on_source` column it writes, needs to know this exception exists before changing either.

## It undoes itself

A roster can drop somebody by mistake — a bad fetch, one malformed record.

If they come back, `SeedLegislatorTerms` clears an OBSERVED end date, because the roster naming them is better evidence than Sway once not seeing them. A PUBLISHED date is never cleared: the jurisdiction's own record outranks both.

The caller runs this only after the roster-size floor passes. That floor is not enough on its own — see `UNREPLACED_DEPARTURE_FLOOR` in the source.

## Why the caller (SeedLegislator) gates the retire call

The floor in `SeedLegislator.run` skips the end-of-run reconcile enqueue when the fresh roster is empty or implausibly smaller than the number of legislators the database currently shows as serving.

The floor in `SeedLegislator.run` skips the end-of-run reconcile enqueue when the fresh roster is empty or implausibly smaller than the number of legislators the database currently shows as serving — a sign of a truncated or failed fetch. A warning is logged so the anomaly is visible.

A bad fetch cannot silently retire somebody's terms. The refresh puts anybody it fails to name back into the roster and asks the history source about them, and `SeedLegislatorTerms` changes or deletes a row only against a list that source answered for. A member too new to have any published history keeps every row they had. So the only shrink effect left to guard is the reconcile job, which would otherwise reassign users away from legislators that are merely missing from a bad fetch.

Only past this floor, and the service bounds how many people one run may retire. A locale whose roster keeps departed members declares so and this does nothing.

## Seat-keyed vs. person-keyed rosters: what carries the fix past Baltimore

`#every_entry_was_understood?` is what carries the fix past Baltimore.

A seat-keyed roster can say "district 1, name unknown" and `#accounted_for?` resolves it. A person-keyed one publishes an id and nothing else, so an entry with no id could be ANYBODY, and every person about to be retired might be them. Refusing the whole run is the only safe answer there, and it costs nothing real: the next run with a readable file retires them.

## Why the floor is a flat 3 AND a 5% share, not either alone

The caller's own roster-size floor only stops a fetch smaller than HALF of what is currently serving, so a 60%-complete fetch still reached this service and retired the rest.

`UNREPLACED_DEPARTURE_FLOOR` and `UNREPLACED_DEPARTURE_SHARE` exist to catch what that floor missed, by counting UNREPLACED departures specifically — an election can turn over many seats at once, and there the arrivals cover the departures. A truncated fetch has no arrivals at all, so the unreplaced count is what tells the two apart.

The floor and the share both exist so the rule fits a body of any size. A flat three is a fifth of Baltimore's sixteen seats and 1.5% of Maryland's 195, which would refuse a legitimate run in the larger body if used alone. Real vacancies are a small share of a chamber — Congress runs about five of 535 — while a truncated fetch loses tens of percent, so 5% separates them with room to spare; used alone it would let too few departures through for a small council. `unreplaced_limit` takes whichever is larger, which keeps a small council workable while still catching a large body's truncated fetch.

## Why accounted_for? treats a resolved seat as "still in office" only, never as identity

A person is `#accounted_for?` when the roster names their `external_id` directly, OR when the roster names their SEAT without being able to say who fills it (an unidentified entry).

Either way they have not left. A seat may only answer "still in office" here — it can never answer "these two are the same person," which is the line the identity model draws between a seat and an identity. `#departed` compares on `external_id` specifically, never on a name or a seat alone, because that column now holds the same value the roster would build for a person's identity — comparing on anything looser is what puts one person's record onto another.

## Why an arrival is defined as "a currently-unmatched roster entry," not a raw headcount

`#arrivals` counts roster entries whose `external_id` does NOT already match an existing `Legislator` row.

An arrival is what makes a departure believable — somebody took the seat — so counting only entries that are genuinely NEW (not merely re-fetched incumbents) is what keeps `#departures_are_believable?` from being fooled by a roster that simply re-lists everyone already in the database.

## Why a refusal is reported as well as logged

`#refuse` both logs a warning and calls `Sentry.capture_message`.

A refusal to act is the one outcome nobody would otherwise see: `db:seed` writes only to the deploy log and raises no exception, so a real departure this service declined to record would go unrecorded in total silence without the Sentry report (development and test report to the local collector specifically so this kind of silent-refusal case is visible there too, not just in production).

## Why retirements are reported as one message per run, not one per person

`#report_retirements` sends a single Sentry message covering every legislator retired in one run, rather than one message per person.

An election can retire a whole city council at once, and fifteen separate reports of what is, in aggregate, one normal event would be noise a person has to wade through to find something actually unusual.

## Why end_current_term! writes with update_columns, not update!

Every seeding path in this codebase avoids ActiveRecord callbacks for the same reason.

Every seeding path in this codebase avoids ActiveRecord callbacks for the same reason: an `after_commit` firing here would rewrite score rows in the middle of a seed that runs on every container boot, turning a routine boot-time reconcile into an unbounded cascade of score recomputes. `update_columns` writes the columns directly and skips callbacks entirely.
