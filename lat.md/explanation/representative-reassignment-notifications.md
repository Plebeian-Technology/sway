---
lat:
  mode: explanation
---

# Representative reassignment notifications

When election turnover or redistricting changes a user's elected representatives, Sway notifies voters and provides direct profile links. The system reconciles assignments silently and alerts users asynchronously.

## Observation seam and non-interference

Reconciliation of user districts and legislators remains owned by `ReconcileUserDistrictsService`. Notification observation executes immediately after transaction commit in an isolated error block.

The observer receives precomputed diff sets and in-memory collections from `ReconcileUserDistrictsService#apply_diff`. Executing outside the database transaction guarantees that notification creation never rolls back voter district link persistence or disrupts ActionCable score refresh broadcasts. Failures within the observer are captured and logged without raising exceptions to the caller.

## Four reassignment transition scenarios

The observer categorizes diff sets into four distinct civic representation transitions. Each transition records previous and current district and legislator entities.

The four transitions handle all combinations of redistricting and electoral turnover:
1. District changed: Detected when stale and new district identifiers are both present, indicating geographic movement or boundary redistricting. Outgoing and incoming representatives are paired across districts.
2. Successor seeded: Detected when district identifiers remain unchanged while legislator identifiers differ, indicating term turnover for the same seat.
3. Vacant seat: Detected when an outgoing representative concludes their term with no incoming successor seeded, persisting an empty current legislator reference.
4. Vacancy filled: Detected when an incoming representative takes office in a previously vacant district seat.

## Deduplication and SQLite partial unique indexes

Multiple reconciliation runs must never generate duplicate notifications or un-dismiss previously acknowledged alerts. Database constraints enforce idempotency across nullable foreign keys.

Because standard SQL unique indexes allow multiple rows with null values, the schema defines three disjoint partial unique indexes on `representative_reassignments`: one for full transitions where both legislators exist, one for vacant seats where the new legislator is null, and one for filled seats where the previous legislator is null. Combined with application-level lookups and unique constraint error rescues, repeated seeder runs remain completely idempotent.

## Notification delivery and preference governance

Outbound notifications respect user channel preferences and debounce multi-seat turnover into consolidated digests. Delivery runs asynchronously on Solid Queue's default queue.

Users control outbound delivery through the `legislator_updates` key in `NotificationPreference`, which defaults to disabled. When transitions occur, an asynchronous delivery job executes with a two-minute debounce delay. The job atomically claims all pending delivery records for the user within a database transaction, sending a single digest email via ActionMailer and dispatching push notifications.

## Frontend presentation and banner dismissal

Active reassignments render in an alert banner at the top of authenticated pages above the main content slot. Users review updated representation and dismiss banners with immediate persistence.

The banner component mounts in `AuthLayout`, providing universal visibility across all authenticated pages. [[app/controllers/application_controller.rb#ApplicationController#pending_representative_reassignments_prop]] memoizes the pending notifications per request with preloaded previous/new legislators, districts, and terms so the `reassignment_notifications` and `representative_reassignments` shared props execute a single query and serialization pass. Each notification displays contextual copy, deep links to the new representative's profile, and a dismiss button. Dismissal triggers an optimistic unmount on the client while persisting a timestamp to `dismissed_at` in SQLite, permanently preventing recurrence across sessions and devices.

## Browser examples confirm the destination page before checking absence

The vacant-seat example retains an active assignment in another locale so Congress can render an empty list without changing the account's authenticated state.

It waits for the current tab panel before asserting that the former representative is absent. This marker distinguishes a loaded empty roster from a redirect or unfinished page. [[identity-and-access#Registration is asynchronous by necessity]] owns the registration predicate that makes the second assignment necessary.
