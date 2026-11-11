---
mode: explanation
summary: "Why the notification delivery browser spec asserts unconditionally on a real DOM role, a real database column, and the queued job rather than the outbound Twilio call."
status: agent-extracted
related: []
---

<!-- vale Vale.Spelling = NO -->

# Notification delivery flow: what gets asserted and why

`spec/system/notification_delivery_spec.rb` drives the user turning on push
notifications, turning on SMS, and then the Bill of the Week path queuing a
text message for every eligible user. Every check in that spec runs
unconditionally — nothing is skipped depending on what the page happens to
be showing:

- The SMS control is clicked outright. It is a checkbox, not a switch, and
  the spec pins `role=checkbox` deliberately. Twilio A2P 10DLC registration
  requires that consent to receive text messages be an explicit checkbox that
  is unchecked by default, and a carrier reviewer compares the live control
  against the consent wording submitted to Twilio. A toggle switch is not
  consent language and caused part of a campaign rejection. The control is the vendored shadcn `Checkbox`, which is
  Radix-based and renders `role=checkbox`; an earlier revision of this
  paragraph described a MUI Switch with a `FormControlLabel` wrapper, which
  had already stopped being true when MUI was quarantined to the
  since-deleted V1 tree.
- `@user.reload.sms_notifications_enabled` is read from the real
  `users.sms_notifications_enabled` column, not inferred from the page.
- The queued-job check names `SmsDeliveryJob` specifically. The Bill of the
  Week path (`app/services/sms_notification_service.rb`) runs: creating a
  `BillNotification` fires its `after_create_commit :notify` hook, which
  calls `SmsNotificationService.send_bill_of_the_week_notification(bill)`,
  which calls `SmsDeliveryJob.perform_later(to: user.phone, body: ...)` once
  per user. The right thing to assert is `have_enqueued_job(SmsDeliveryJob)`,
  not a fake Twilio call: `SmsDeliveryJob` is the thing that talks to
  `Twilio::REST::Client#messages`, and the point of this spec is that the
  job gets queued — not that the HTTP call which actually sends the text
  goes out.

## Why the save-confirmation read is gated on the flash notice, not the address

Reading `@user.reload.sms_notifications_enabled` right after the save has
to wait for something. The address is NOT a safe gate: this example
navigates to `/notifications?tab=sms` itself two steps earlier, so a check
against that URL is already true before the save POST is even sent, and
would pass at once — letting the database read race the POST. That is the
failure this example showed about one full-suite run in six. The flash
notice cannot be on screen until `update_settings` has written the row and
redirected, so gating on `have_text("Notification preferences updated.")`
is what actually orders the read after the write. Its sibling in
`spec/system/organization_follows_spec.rb` is gated the same way, for the
same reason. That the redirect keeps the tab rather than sending the
operator to a bare `/notifications` is checked where it can
fail — `spec/requests/notifications_controller_spec.rb` — not here.

## Why the Bill of the Week service is called directly instead of through the real job chain

In production the chain is: `OnBillBecomesBotwNotifyUsersJob#perform` walks
every locale and creates a `BillNotification` for each eligible bill; that
record's `after_create_commit :notify` hook calls
`SmsNotificationService.send_bill_of_the_week_notification`, which queues
`SmsDeliveryJob` for every user with `sms_notifications_enabled`. This
system spec runs inside a database transaction that is rolled back at the
end, and an `after_create_commit` hook never fires until the transaction
actually commits — so the spec calls the service the hook would have
called directly, rather than creating a `BillNotification` and waiting for
a commit hook that a test transaction will never trigger. The rest of the
chain (the job walking locales, the commit hook itself) has its own unit
tests.
