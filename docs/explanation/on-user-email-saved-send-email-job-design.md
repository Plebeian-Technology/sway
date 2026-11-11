---
mode: explanation
summary: "Why OnUserEmailSavedSendEmailToLegislatorJob only retries pre-send failures, uses update! to guard the sending-state transition, and always leaves the row re-triggerable on any rescue."
status: agent-extracted
related: []
---

<!-- vale Vale.Spelling = NO -->

# Why `OnUserEmailSavedSendEmailToLegislatorJob` is shaped the way it is

`Net::SMTPServerBusy` lives in `net/smtp`, which ActionMailer only
auto-requires under the `:smtp` delivery method (production) — the job
`require`s it explicitly so the `retry_on` class list resolves in every
environment.

## Why only two exception classes are retried

Retry ONLY the failures known to have happened before the message was
handed over. Sending is not repeatable — `deliver_now!` pushes straight out
over SendGrid's SMTP — so a retry must never be able to re-send a message
the server already accepted.

- `Net::OpenTimeout` — the connection never opened, so nothing was sent.
- `Net::SMTPServerBusy` — the server replied 4xx before the message body
  was sent, so it turned the mail away instead of queuing it.

`Net::ReadTimeout` and `Errno::ECONNRESET` can fire AFTER the server took
the message body, while the job waits on its closing "250 OK". Retrying
those would send the legislator (and the user copied on it) a duplicate
email. They fall through to the job's `rescue`, which parks the row at
`failed` to wait for someone to re-trigger it by hand.

## Why the sending-state transition uses `update!`, not `update`

`update!` and not `update`: if the row cannot be moved to `sending`, raise
instead of quietly emailing on behalf of a row whose status write was
rejected. The `rescue` below catches that raise, sets the row back to
`failed`, and re-raises, so a rejected status change never reaches
`send_email`.

## Why the rescue always leaves the row re-triggerable

Always leave the row in a state it can be tried from again. `sendable?`
accepts `failed?`, so both `retry_on`'s re-enqueue and a person
re-triggering it can pick the row up. Without this, a raise stranded the
row at `sending` forever: not sendable, and not re-triggerable either,
because the controller uses `find_or_create_by` and would keep finding the
stuck row.
