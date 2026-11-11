---
lat:
  mode: explanation
---
# Fetching a Congress roll call

A published Congress vote is addressed by a number that is only unique inside one year, so almost everything on this page exists to stop Sway pairing a bill with somebody else's vote.

## Roll-call numbering restarts every year

The clerk files a roll call under the year it was taken and starts counting again each January, so the year in the request has to be the year the vote happened rather than the year the request is made.

House roll-call votes use dual-stage acquisition in [[app/scraper/scraper/congress/house/legislator_votes.rb#LegislatorVotes]]: Stage 1 queries the official Congress.gov v3 REST endpoint `/v3/house-vote/{congress}/{session}/{rollCallNumber}/members` with parameters `api_key` and `format: :json` via [[lib/sway/faraday_stack.rb#FaradayStack#congress_gov]], and Stage 2 falls back to `clerk.house.gov` XML (`https://clerk.house.gov/evs/{year}/roll{NNN}.xml`) whenever Stage 1 raises [[app/scraper/scraper/congress/roll_call_unavailable.rb#RollCallUnavailable]]. Real `clerk.house.gov` `<legislator>` elements omit `first-name` and `last-name` attributes (carrying `name-id`, `sort-field`, `unaccented-name`, `party`, `state`, and `role`), so Stage-2 voter extraction reads the member surname from `unaccented-name`, `sort-field`, or element text and does not require `first-name`. Both [[app/scraper/scraper/congress/house/legislator_votes.rb#LegislatorVotes]] and [[app/scraper/scraper/congress/senate/legislator_votes.rb#LegislatorVotes]] derive the Congress number — the 1st met in 1789 and each runs two years — and the session number, where an odd year is session 1 and an even year session 2, from the vote year. Either way, asking for an old number under today's year returns a different vote and records its members as though they had voted on this bill.

[[app/services/congress_legislator_vote_update_service.rb#CongressLegislatorVoteUpdateService]], [[app/services/legislation/adapters/generic_vote_adapter.rb#GenericVoteAdapter]], and [[app/jobs/legislator_vote_fetch_job.rb#LegislatorVoteFetchJob]] therefore take the fetch year from the bill's own chamber vote dates, and skip a roll-call number whose chamber has no vote date rather than falling back on the clock. [[app/jobs/legislator_vote_sweep_job.rb#LegislatorVoteSweepJob]] leaves a settled bill alone for the same reason: its newest chamber vote is in a past year and its rows are already recorded, so a daily re-fetch of that number could only land on a fresh, unrelated vote.

## Senate vote fetch resilience against upstream HTML errors

Senate roll-call acquisition implements dual-stage fetching to protect automated ingestion against upstream web application firewall blocks and challenge pages that intermittently reject official XML feeds.

The primary `senate.gov` XML endpoint sits behind Akamai Bot Manager defenses that periodically reject automated requests with HTTP 403 Forbidden responses or HTML challenge pages (`<!DOCTYPE html>`). When this occurs, XML parsers receive HTML rather than roll-call data, causing ingestion to fail.

[[app/scraper/scraper/congress/senate/legislator_votes.rb#LegislatorVotes]] catches HTTP transport errors and detects non-XML HTML responses during the primary fetch stage. When primary fetching fails, the scraper logs a structured warning via [[lib/sway_logging.rb#SwayLogging#warn]] with event `senate_roll_call.primary_fetch_failed` and initiates a secondary fallback request to Voteview (`https://voteview.com`) public JSON endpoints.

The fallback stage queries the session roll-call index at `static/data/out/rollcalls/S{congress}_rollcalls.json` to resolve the Voteview roll-call identifier, fetches the complete vote payload from `api/download`, and normalizes Voteview's schema into the shared internal roll-call Hash structure expected by [[app/scraper/scraper/congress/senate/legislator_votes.rb#LegislatorVotes#identity]] and [[app/scraper/scraper/congress/senate/legislator_votes.rb#LegislatorVotes|LegislatorVotes#process]]. Voteview index updates typically lag floor action by several weeks (on October 27, 2026, the index was last modified October 1, 2026), so recently held roll calls whose primary XML is challenged will not yet appear in the fallback index.

When both the primary XML source and Voteview fallback fail, the scraper logs `senate_roll_call.fallback_fetch_failed` and raises [[app/scraper/scraper/congress/roll_call_unavailable.rb#RollCallUnavailable]]. Rather than returning an empty result or dispatching premature alerts, the exception propagates to [[app/jobs/legislator_vote_fetch_job.rb#LegislatorVoteFetchJob]], where it is retried with backoff.

## Why a fetched record has to name the bill's own vote

Asking by number and year proves nothing about which vote answered, so the record's own account of itself is compared against what the bill says before anything is written.

The bill's identifier used to be passed to the scraper and never read at the
other end, which meant nothing noticed a number pointing somewhere else. What
the clerk publishes alongside the tally — the document name, the question, the
title and the day — is the evidence that settles it, and the day is the part
that has to agree.

Two shapes of that day are both correct. Most Congress bills store midnight in
Washington written as UTC, and a nomination such as PN11-7 stores midnight UTC
itself; refusing either would refuse a correct pairing. The Senate also ends its
title with a newline and pads its fields, so the identity strips its text before
it reaches the comparison or the logs.

## Why procedural roll calls name no bill

A procedural vote names no measure in clerk or Congress.gov records, so the scraper leaves the document name empty rather than matching a bill.

Procedural roll calls—such as quorum calls, motions to table, or motions to adjourn—do not address specific legislation. In clerk XML, the clerk writes non-bill markers such as `QUORUM` where a bill number normally appears; in Congress.gov REST JSON, `legislationType` and `legislationNumber` are absent. Leaving `document_name` as `nil` prevents [[app/scraper/scraper/congress/roll_call_identity.rb#RollCallIdentity]] from asserting that a procedural action is a vote on the bill.

## Why parse date rescues ArgumentError

Unparseable date strings return nil rather than raising, and the rescue catches ArgumentError because Date::Error inherits from it and RBS types it.

Both House and Senate scrapers normalize date strings using [[app/scraper/scraper/congress/house/legislator_votes.rb#LegislatorVotes#parse_date|House parse_date]] and [[app/scraper/scraper/congress/senate/legislator_votes.rb#LegislatorVotes#parse_date|Senate parse_date]]. In the Ruby standard library, `Date.parse` raises `Date::Error` when given invalid syntax. Because `Date::Error < ArgumentError`, rescuing `ArgumentError` catches invalid date syntax cleanly while aligning with the method signatures that RBS and Steep validate. Returning `nil` delegates the date mismatch decision to [[app/scraper/scraper/congress/roll_call_identity.rb#RollCallIdentity#taken_on?]] and [[app/services/congress_legislator_vote_update_service.rb#CongressLegislatorVoteUpdateService#verify_record!]].

## A vote on something else is not a position on the bill

A member can vote for a procedural motion and against passage, so recording the first as their position states something they never said.

In [[app/services/congress_legislator_vote_update_service.rb#CongressLegislatorVoteUpdateService#verify_question!]], every Senate cloture question or title is refused with [[app/scraper/scraper/congress/roll_call_not_on_the_bill.rb#RollCallNotOnTheBill]], and [[app/scraper/scraper/congress/roll_call_question.rb#RollCallQuestion#counts_as_position?]] requires the question put to the chamber to express an actual passage or adoption position on the measure rather than merely matching a roll-call number or procedural step.

## Why chamber roll-call updates are isolated

Each chamber's roll call is fetched and verified independently so that a permanent refusal or network error in one chamber does not prevent the other chamber's votes from refreshing.

A congressional bill often has roll calls recorded in both the House and the Senate. Because floor procedure differs across chambers, one chamber's recorded roll call may represent a procedural action—such as a cloture motion or motion to table—that does not count as a position on the measure itself, while the other chamber voted on final passage. Procedural roll calls fail question verification with [[app/scraper/scraper/congress/roll_call_not_on_the_bill.rb#RollCallNotOnTheBill]], which is a permanent refusal that recurs on every subsequent run.

Fetching both chambers sequentially without isolation causes a refusal in the first chamber to abort the entire update. The second chamber's votes are never fetched, leaving them permanently stale while the error report mentions only the first chamber.

On the production path, [[app/jobs/legislator_vote_fetch_job.rb#LegislatorVoteFetchJob]] routes Congress bills to [[app/services/congress_legislator_vote_update_service.rb#CongressLegislatorVoteUpdateService]]. The service isolates House and Senate runs, executing roll-call identity verification ([[app/services/congress_legislator_vote_update_service.rb#CongressLegislatorVoteUpdateService#verify_record!]], [[app/scraper/scraper/congress/roll_call_identity.rb#RollCallIdentity#taken_on?]], [[app/services/congress_legislator_vote_update_service.rb#CongressLegislatorVoteUpdateService#verify_question!]]) before persisting each chamber's member votes. Any valid votes fetched from an unrefused chamber are persisted, while errors encountered across either chamber are aggregated and re-raised at completion. When a chamber raises an exception—such as [[app/scraper/scraper/congress/roll_call_unavailable.rb#RollCallUnavailable]]—the sponsor-inference fallback is withheld: an unfetchable roll call suppresses sponsor inference, ensuring that missing roll-call data does not fabricate synthetic positions for unattempted or failed delegations.

## The roster a roll call is matched against is the vote day's

A 2024 roll call is matched against the people serving in 2024, not against whoever is serving when the fetch runs.

Matched against today's roster instead, 53 of the 405 published votes on bill
hr192 went missing, and nothing said so — a departed member's vote simply has
nobody to attach to. Which term was running on a given day is decided by
[[current-legislator-term]].

## Nobody is the honest answer when two people cannot be told apart

A roster lookup that cannot distinguish two people returns neither of them rather than guessing.

South Carolina's Senate seat changed hands mid-term, husband to wife. Terms
stored as whole years leave both reading as running in 2026, and a roll-call
line carries a title and a surname, which cannot separate two senators from the
same state. The published start date recorded on a term is what eventually
separates them; until it is known, an unresolvable pair produces no match at
all.

## Why the test suite fakes the scrapers with an agreeing identity

Both scrapers are faked for every example so the [[app/models/roll_call.rb#RollCall]] creation callback never reaches the network, while the fixture agrees on day and question so tests start from an unrefused baseline.

Creating a [[app/models/roll_call.rb#RollCall]] queues [[app/jobs/legislator_vote_fetch_job.rb#LegislatorVoteFetchJob]], which immediately runs [[app/services/congress_legislator_vote_update_service.rb#CongressLegislatorVoteUpdateService]] under the inline test queue adapter. Without scraper doubles, creating any test roll-call record would attempt live network calls to congress.gov.

The default identity fixture (`agreeing_identity`) specifies `"On Passage of the Bill"` and date `2024-06-18`. `"On Passage of the Bill"` is standard Senate phrasing that also satisfies the House passage question parser, allowing one double to serve both chambers without raising [[app/scraper/scraper/congress/roll_call_not_on_the_bill.rb#RollCallNotOnTheBill]]. Stating an explicit date satisfies [[app/scraper/scraper/congress/roll_call_identity.rb#RollCallIdentity#taken_on?]] and supplies a valid date for [[app/services/legislator_roster.rb#LegislatorRoster]] term matching, preventing [[app/scraper/scraper/congress/roll_call_mismatch.rb#RollCallMismatch]]. Test contexts verifying refusal or mismatch override these defaults explicitly.

## Why Senate roll-call matching uses surname and state with a title fallback

Senate XML roll-call rosters identify members by surname and two-letter state postal code rather than full name because official Senate printings frequently abbreviate or alter given names.

Including given names drops match rates across roll calls because Sway stores full legal names from the unitedstates project while Senate XML prints nicknames (for example, "Maggie" for "Margaret Wood"). When multiple legislators share a surname and state, [[app/services/legislator_roster.rb#LegislatorRoster]] prefers terms titled "Sen.", falling back to any active term in that state when historical term records omit the title.

## How RollCallQuestion separates passage from procedural motions

[[app/scraper/scraper/congress/roll_call_question.rb#RollCallQuestion]] matches chamber-specific passage openings and carves out concurrence with an amendment so procedural votes are never recorded as bill positions.

In the House, [[app/scraper/scraper/congress/roll_call_question.rb#RollCallQuestion]] matches by opening phrase because the clerk appends clauses such as `, as Amended` or `Objections of the President Notwithstanding`, and most House measures pass under suspension of the rules rather than plain passage. In the Senate, [[app/scraper/scraper/congress/roll_call_question.rb#RollCallQuestion]] matches the whole question while [[app/scraper/scraper/congress/roll_call_question.rb#RollCallQuestion]] (`on the motion`) is excluded from the direct allowlist because procedural motions and concurrences share that question string and are distinguished only by `title` against [[app/scraper/scraper/congress/roll_call_question.rb#RollCallQuestion]]. [[app/scraper/scraper/congress/roll_call_question.rb#RollCallQuestion#concurrence_with_amendment?]] rejects concurrences matching [[app/scraper/scraper/congress/roll_call_question.rb#RollCallQuestion]] because concurring with an amendment returns the measure to the other chamber rather than adopting final text. [[app/scraper/scraper/congress/roll_call_question.rb#RollCallQuestion#known?]] and [[app/scraper/scraper/congress/roll_call_question.rb#RollCallQuestion#refused]] separate recognized procedural questions from unseen question strings so new phrasing is logged while still refused.
