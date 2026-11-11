---
lat:
  mode: explanation
---
# Identifying a congressional roll call

A roll-call number is unique only within one year, so asking a chamber for a number proves nothing about which vote comes back. What a fetched record says it is — the document voted on, the question put, and the day — is what gets checked.

## Why the year must be the year of the vote

The year passed to a fetch is the year the vote happened, read off the bill's
own recorded vote time, never the current year.

Both chambers file roll calls under the year they were taken and restart their
numbering every January. Both [[app/scraper/scraper/congress/house/legislator_votes.rb#LegislatorVotes]]
and [[app/scraper/scraper/congress/senate/legislator_votes.rb#LegislatorVotes]]
derive their Congress and session parameters directly from that vote year.
Asking for an old bill's roll number under today's year returns a real record for
a different vote rather than an error — which is exactly what happened when the
code read the clock instead: a 2026 roll call was written onto a 2024 bill,
every day, for weeks.

## Why the record is checked rather than trusted

The bill's own id was once passed to the fetch and never read, so nothing
noticed when the number and year pointed at another bill's vote.

The caller now compares the identity of what came back. The day is the hard
test: a stored roll number paired with the wrong year returns a plausible
record, and its date is the thing that gives it away.

The day is read in two time zones, because both sources print Washington's
local day while some stored times are midnight there and others midnight in
UTC. Either reading may be the one that agrees, so both are tried.

The Senate's document name sits one level below the top of the response. Read
from the top level it was always nil, so the caller's name check could never
agree and warned on every Senate fetch.

On the production path, [[app/jobs/legislator_vote_fetch_job.rb#LegislatorVoteFetchJob]] routes Congress bills directly to [[app/services/congress_legislator_vote_update_service.rb#CongressLegislatorVoteUpdateService]]. Whether fetched from Congress.gov REST responses, clerk.house.gov fallback XML, primary senate.gov XML, or normalized Voteview roll-call structures, [[app/scraper/scraper/congress/roll_call_identity.rb#RollCallIdentity]] extracts the document name, question, and vote date. The service executes [[app/services/congress_legislator_vote_update_service.rb#CongressLegislatorVoteUpdateService#verify_record!]], requiring [[app/scraper/scraper/congress/roll_call_identity.rb#RollCallIdentity#taken_on?]] to match the expected vote date and [[app/services/congress_legislator_vote_update_service.rb#CongressLegislatorVoteUpdateService#verify_question!]] to confirm that the question addresses the bill itself rather than an unrelated motion before any vote row is persisted. When an upstream roll call cannot be fetched or raises an error, the service isolates each chamber and suppresses sponsor inference: an unfetchable roll call suppresses synthetic sponsor inference, ensuring incomplete or failed upstream evidence does not fabricate member positions.

## Why a wrong roll call raises rather than returns

A record from a different day, and a right-day record that is not a vote on the
bill, both raise an error that names a person as the reader.

Neither is an `ArgumentError`, deliberately: the fetch job discards those, and
these two need somebody to look. The commonest right-day-wrong-vote case is a
vote to end debate. A member can vote for cloture and against passage, so a
vote on a step along the way is not their position on the bill, and recording
it as one would misreport them.

## How RollCallIdentity normalizes and compares bill numbers

[[app/scraper/scraper/congress/roll_call_identity.rb#RollCallIdentity]] folds House Clerk, Senate XML, and Sway bill identifiers into one lowercase alphanumeric string before comparing them.

The House Clerk XML, the Senate roll-call XML, and `Bill#external_id` format the same measure differently (such as `H R 192`, `S. 5`, and `hr192`), so stripping punctuation and whitespace leaves only the letters and digits they share. [[app/scraper/scraper/congress/roll_call_identity.rb#RollCallIdentity#names?]] returns `false` whenever either `document_name` or `external_id` is blank so two empty identifiers never normalize to the same empty string and match.
