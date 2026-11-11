---
lat:
  mode: explanation
---

# OrganizationBillPosition's after_commit callbacks

`OrganizationBillPosition` registers two `after_commit` callbacks that each guard a side effect other code must not accidentally duplicate or skip.

## notify_followers_on_change: the guard and the change-label rule

The follower-notification callback only fires when TWO things are both true: the position is active AFTER the commit (`active && NOTIFIABLE_FIELDS.any?

{ |f| saved_change_to_attribute?(f) }`), and at least one of `NOTIFIABLE_FIELDS` (`active`, `support`, `summary`) actually changed. Requiring `active` to be true after the commit is what blocks the soft-delete path from notifying — a soft-delete flips `active` to `false`, which fails the `active` half of the guard.

`#notify_followers_on_change` itself picks the change label(s) with one rule: if the save flipped `active` from false to true, the label is `[:new_position]` ONLY, even when `support` or `summary` also changed in the very same commit — a brand-new position is a new position, not a new position that also happens to carry an edited stance. Only on a later, separate commit do support-only or summary-only edits get their own fine-grained labels (`:support_change`, `:summary_change`).

The `rescue Exception` wrapper mirrors `BillNotification#notify`'s pattern, so a notification-delivery failure can never roll back the approval transaction that already committed — the position change is real regardless of whether anyone got told about it.

### Why the change-label spec asserts the exact arguments, not a negative

`organization_bill_position_spec.rb`'s "enqueues EXACTLY one job with EXACTLY \[:new_position]" example asserts the exact enqueue arguments positively, with `.exactly(:once)`.

An earlier version asserted a negative instead (`not_to have_enqueued_job(...).with([:support_change])`), which passed even if no job ran at all, or if the job ran with completely different arguments. Asserting the positive shape means a future regression to `["new_position", "support_change"]` no longer matches `["new_position"]`, so the example actually fails instead of passing by accident.

## enqueue_interesting_score_recompute: soft-deletes and a tolerated double-enqueue

This callback uses `after_commit`, not `after_save_commit`, specifically so a soft-delete (`active: false` via an ordinary `#save`/`#update`) also triggers a recompute.

This callback uses `after_commit`, not `after_save_commit`, specifically so a soft-delete (`active: false` via an ordinary `#save`/`#update`) also triggers a recompute — a position flipping off matters to a bill's score exactly as much as one flipping on.

`ReplaceBillOrgPositionsService`, the bulk admin-approval path, also enqueues `RecomputeBillInterestingScoreJob` by hand, once per row, on top of this callback firing once per row too. That double-enqueue is deliberate and harmless — `RecomputeBillInterestingScoreJob` dedupes identical enqueues — so it must NOT be read as evidence that this callback is being skipped there, and no explicit notification call should be added back to compensate. Doing so would double-send every follower's SMS and push notification, unlike the harmless job dedupe.
