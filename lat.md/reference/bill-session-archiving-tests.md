---
lat:
  require-code-mention: true
---
# Bill session archive tests

Behavioral checks for [[bill-session-archiving]] cover session boundaries, locale isolation, preserved records and list visibility.

## Active pipeline exclusion

Archive application refuses while the same locale's pipeline runs or awaits a summary batch, preserves eligible bills on refusal, and becomes available after completion; another locale's pipeline does not block it.

## Executing pipeline exclusion

Workers honor stops made while waiting and retain archive exclusion until executing services exit, even if an operator stops the run.

## Batch readback exclusion

Summary result readback holds the locale lock even for a stopped run so archiving cannot overlap remaining batch persistence work.

## Cross-process locale exclusion

Independent processes cannot enter the same locale operation together; pipeline work waits behind archiving, other locales proceed, and normal or exceptional exit releases the lock.

## Eligibility and locale isolation

Preview includes only older unfeatured bills in the requested locale, including legacy rows without a session; current, future and scheduled bills remain excluded and preview writes nothing.

## History and repeat execution

Apply preserves bill, user vote and score records, makes the bill inactive and leaves its first archive timestamp unchanged when the operation runs again.

## Session guards

A missing active session or one that has not started rejects the operation without stamping any bill.

## Overlapping and active sessions

Bills assigned to a session continuing beyond the rollover boundary or still marked active remain outside the candidate set.

## Archive query exclusion

Ordinary queries, associations, identifier lookups and reloads exclude archives; explicitly unscoped console queries retain access.

## Command preview and apply

The command lists candidate identifiers without writing by default and stamps records only when the apply argument is present.

## Command input validation

Missing or unknown locale names and invalid mode arguments fail without archiving records.

## Public list visibility

Archived bills contribute neither to the public count nor to deferred bill rows.

## Admin picker and direct access

The Bill Creator picker omits archives and direct admin edit requests return 404, while the public bill detail page remains viewable read-only.

## Ingestion preserves the archive

Repeated upstream ingestion skips an archived identity without returning a bill, creating a duplicate or changing retained metadata.

## Ingestion recovery checks the archive once

Live uniqueness recovery under the locale lock performs one retained-archive identity existence read, returns the winning bill, updates metadata and retains one physical row.

## Scheduling from a stale record

Scheduling through an instance loaded before archiving fails and leaves the retained record archived and unscheduled.

## Stale deletion preserves history

Destroying an instance loaded before archiving fails before dependent callbacks, preserving its bill, vote and score rows.

## Report visibility

Admin report lists, counts and direct lookups omit reports for archived bills while their rows remain stored.

## Organization visibility

Membership and public positions omit archives; archived position edits and pending-change approvals return 404 without altering retained history.

## Vote visibility

User vote responses omit archived bills and new votes cannot be cast on them, while previous vote records remain stored.

## Disk ingestion skips archives

Disk reseeding skips retained archived identities without creating new pipeline work or rolling back live intake.

## Batch ingestion skips archives

A batch containing an archived bill settles its live siblings without writing archived summaries or retrying archived answers.

## Partner reporting visibility

Partner reporting omits archived articles from rows and totals without deleting stored article records.

## Queued outreach skips archives

An email queued before archiving becomes unsendable even when its cached bill association still holds a previously visible instance.

## Queued scores skip archives

A score update queued before archiving stops without recomputing scores or deleting its retained user vote.

## Queued organization notifications skip archives

Organization notification jobs ignore retained positions whose bills have since been archived.

## Successful readback query budget

Successful live answers persist summaries and positions and settle the batch and run without standalone bill-by-id existence probes from readback.

## Retry readback query budget

A transport failure retains its successful summary, submits only the owed positions retry and leaves the run waiting without standalone bill-by-id existence probes from readback.

## Visible pipeline traversal query budget

Visible unfinished bill stages dispatch their services, persist successful results and finish the run without retained-archive existence reads during uncached traversal.

## Missing pipeline identity outcome

An ordinary missing bill records a failed stage while a visible sibling succeeds, leaving the run partial without archive replay setup.
