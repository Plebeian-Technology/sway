---
lat:
  mode: explanation
---

# Bills controller roll-call synchronization

The Bills controller synchronizes roll-call vote records in place rather than creating new entries when operators correct roll-call numbers.

Saving a bill with house or senate roll-call numbers synchronizes the bill's [[app/models/roll_call.rb#RollCall]] record.

## In-place roll-call update and purging

Updating the newest existing roll-call record in place guarantees that each bill converges to exactly one roll-call record.

Using find-or-create keyed on roll-call numbers previously left orphaned rows behind whenever an operator corrected a number. The controller now finds the latest record, assigns the incoming numbers, saves it, and purges any duplicate rows for the bill.

## Re-fetching legislator votes after roll-call correction

Correcting a roll-call number on an existing record requires explicitly re-fetching legislator votes because updating in place does not trigger the create hook.

A newly created [[app/models/roll_call.rb#RollCall]] enqueues [[app/jobs/legislator_vote_fetch_job.rb#LegislatorVoteFetchJob]] via its after-create callback. When an existing record's roll-call numbers change, after-update fires instead, so the controller enqueues [[app/jobs/legislator_vote_fetch_job.rb#LegislatorVoteFetchJob]] directly when roll-call numbers change.
