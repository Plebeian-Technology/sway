---
lat:
  mode: explanation
---
# Pending organization digest entry design

[[app/models/pending_organization_digest_entry.rb#PendingOrganizationDigestEntry]] records pending organization position changes for users configured with daily or weekly notification cadences.

## Why PendingOrganizationDigestEntry is a durable queue

Pending digest rows reside in the primary SQLite database rather than ephemeral memory or external message queues.

Because entries are stored durably, pending notifications survive process restarts, deployment reboots, and scheduled job delays without losing follower updates. Foreign keys are deliberately omitted for organization and bill references because rows are ephemeral queue items claimed and purged during dispatch.

## Why CADENCES is validated as defense-in-depth

The model validates cadence values against CADENCES to prevent malformed rows from leaking into storage.

The database column enforces not-null constraints but allows arbitrary strings. Validating cadence prevents typos from silently evading dispatch filters and stranding orphan records.

## Why dispatch_period uses keyset pagination by recipient

The dispatcher paginates across distinct recipient user identifiers using a monotonic keyset cursor.

Batching across distinct recipient identifiers bounds process memory while ensuring all pending updates for a follower are consolidated into a single digest. Keyset pagination ensures stable cursor advancement even as processed entries are deleted during dispatch.

## Why dispatch_period selects with no created_at window

The dispatch query selects pending records without restricting the creation timestamp.

Deleting claimed rows during dispatch acts as the completion marker. Omitting a timestamp window prevents delayed or recovered scheduled jobs from stranding valid pending updates.

## Why rows are claimed before sending

Pending rows are transactionally deleted before notifications are dispatched to external notification fanouts.

Delivery enqueues jobs into a separate Solid Queue database, preventing two-phase transactional commit. Claiming records prior to delivery guarantees at-most-once delivery and eliminates duplicate notifications across concurrent runs or retries.

## Why the master gate is re-checked at dispatch

Follower preferences are verified during dispatch as a second line of defense.

Users may alter or disable their notification preferences after an entry is enqueued. Re-checking the master preference immediately before fanout suppresses unwanted messages and clears stale queue rows.
