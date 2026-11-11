---
mode: explanation
summary: "Why ReplaceBillOrgPositionsService validates the whole batch before writing anything, upserts by (bill, organization) instead of deleting and re-inserting, and enqueues its score recompute after the transaction closes."
status: agent-extracted
related: [docs/explanation/org-position-approval-guard-chain.md, docs/explanation/organization-bill-position-notification-callbacks.md, docs/explanation/recompute-bill-interesting-score-job-design.md]
---

<!-- vale Vale.Spelling = NO -->

# Why `ReplaceBillOrgPositionsService` is built the way it is

`ReplaceBillOrgPositionsService` replaces the whole set of organization
positions on one bill in a single admin request. This used to be a
roughly 190-line controller action mixing eight rejection cases, the
write itself, a score recompute, and activity-log entries; all of that
now lives here, and every error code, message, and HTTP status the
service returns is exactly what the controller used to send.

The submitted list is the complete, authoritative set of ACTIVE positions
for the bill: organizations in the list are saved in place and switched
on; organizations missing from the list are switched off. Nothing is ever
deleted, so row ids and the history of changes survive, and the
follower-notification hook that runs after each save can describe what
happened correctly.

## Why the bill id is validated before anything is touched

A request with no `bill_id` used to run
`where(bill_id: nil).destroy_all`, quietly deleting every stray position
row in the table with no `bill_id` set, and then crash trying to insert
rows with no bill attached. Checking that exactly one `bill_id` was named,
and that it names a real bill, happens before any write.

## Why every position is validated as a batch BEFORE any position is validated individually, and both before any write

Three believable-looking bad requests used to slip past a batch-level-only
check and either crash or silently save bad data:

1. **One position with no bill id.** The batch check drops nils before
   counting, so it passed, and the bulk insert then crashed because that
   one row had a different set of keys from the others.
2. **One position with no `summary` key at all.** Rails only keeps keys
   that were actually sent, so again the rows had mismatched keys and the
   bulk insert crashed.
3. **A `summary` that is an empty string.** A bulk insert skips the
   model's "must be present" validation entirely, and the database is
   happy to store `""`, so a useless row was saved with no complaint at
   all.

Every position is checked for completeness (`bill_id`, `organization_id`,
a non-blank `summary`) before ANY write happens, closing all three holes
at once.

## Why organization ids are validated before the delete runs

An unknown or duplicated `organization_id` used to only surface as a raw
database error — and because the old code ran the "switch off missing
organizations" delete FIRST and it committed immediately, that database
error arrived AFTER every previously-approved position on the bill had
already been wiped out. Checking organization ids for uniqueness and
existence before touching anything at all is what stops a malformed
request from wiping out real, previously-approved data on its way to
failing.

## Why the write upserts by `(bill, organization)` instead of deleting and re-inserting

Organizations in the submitted list are saved IN PLACE: the service finds
the existing row by `(bill, organization)` — there is a unique index on
that pair — or builds a new one, then saves it, the same way
`ApproveOrgPositionService` does. Nothing is deleted and re-inserted.
Saving through the model keeps the row's id, its `created_at`, and its
whole change history intact; it also runs the model's validations and
lets the after-save hook describe what happened correctly — a first-time
activation reads as a new position, while a change to an already-active
row reads as a change of stance or wording (see
[the notification callbacks doc](organization-bill-position-notification-callbacks.md)).

Keeping ids stable also keeps the "have we already notified people about
this?" marker honest (see
[the notify job's sent-marker doc](notify-organization-followers-job-design.md)).
The old delete-and-reinsert approach produced a brand-new id every time,
so double-clicking Approve sent a SECOND round of billable SMS and push
notifications to every follower.

Organizations missing from the submitted list are switched off rather
than deleted, with `update!` so their score-recompute hook still runs —
deleting them would have thrown away the audit history. Organizations
present in the list always come back on: re-submitting a previously
switched-off organization turns it back on, which is what an admin
re-approving it means, and a brand-new row is never left switched off by
accident.

## Why a `RecordNotUnique` is retried exactly once

If another request creates the same `(bill, organization)` row in the gap
between this service's lookup and its save, the unique index rejects the
insert. The service retries ONCE, which finds the row the other request
just committed and edits it instead. If the SAME race happens again on
the retry, the service gives up and lets the error propagate rather than
retrying indefinitely.

## Why the score recompute is enqueued even though every changed row already triggers one

`RecomputeBillInterestingScoreJob` is enqueued explicitly at the end of
`#call` even though each individually-changed row's `after_commit`
callback already enqueues one (see
[the callbacks doc](organization-bill-position-notification-callbacks.md)
for why that double-enqueue is deliberate and harmless — the job dedupes
identical enqueues). Re-submitting a list that changes NOTHING triggers no
row-level hook at all, so without the explicit enqueue here, the bill's
score could quietly drift out of date after a genuinely no-op resubmit.

The explicit enqueue happens AFTER the transaction closes, on purpose:
background jobs live in their own Solid Queue database, so a job queued
mid-transaction could start running and read the OLD data before this
transaction's changes are actually committed.

## Why the response body is now a serialized resource

The response body used to be the raw result of the bulk insert. It is now
the saved rows run through `OrganizationBillPositionResource`, the
resource that decides which fields may be public. Nothing in this
repository reads the body today, and the resource's output still includes
the old shape (a list of ids), so no existing caller can be broken by the
change.

## Browser coverage for what a deactivated position looks like

`Bill#organization_bill_positions` returns only ACTIVE positions, so the
bill page's support and oppose cards list only those. Nothing pinned what
a visitor actually sees once a position is switched off — for example
when this service approves a new batch and deactivates the old one —
until `spec/system/bill_org_positions_spec.rb` was written to cover it in
a real browser.
