---
mode: explanation
summary: "Design notes for UserLegislatorEmailsController: the send pipeline and idempotency, why full_name is captured inline, why a missing bill redirects rather than returns bare, and why failed sends are re-enqueued explicitly."
status: agent-extracted
related: []
---

<!-- vale Vale.Spelling = NO -->

# `UserLegislatorEmailsController` design notes

## Why this controller exists and how it stays idempotent

This is the create path for the email-your-legislator feature. An earlier
cleanup deleted the entry point; this controller restores it onto the
live send pipeline: `UserLegislatorEmail` -> `after_create_commit` ->
`OnUserEmailSavedSendEmailToLegislatorJob` -> `UserLegislatorEmailMailer`.

One POST fans out to every one of the user's legislators for the bill's
locale. The `(user_legislator_id, bill_id)` unique index plus
`find_or_create_by` mean repeating the same POST changes nothing.

## Why `wrap_parameters` lists `full_name` explicitly

Rails' params wrapping only picks up `UserLegislatorEmail`'s own column
names, and `full_name` is a USER attribute captured in the same form — it
has to be listed explicitly so the modal's flat Inertia payload lands
inside the `user_legislator_email` params key.

## Why a missing bill redirects instead of returning bare

A missing bill redirects with a flash rather than returning early with no
response — a bare `return` used to produce an empty response that left
the submitting form hanging with no feedback. The local `bill` variable
also narrows the nilable `Bill` type for the steep type checker.

## Why the user's name is captured inline, in this form

There is no separate name-collection endpoint; the send form captures the
user's full name right here, because the mailer signs the outgoing
message with the user's name, so it must be set before sending — the
mailer must never send an unsigned message.

## Why failed sends are re-enqueued explicitly

`after_create_commit` does not fire again when `find_or_create_by` FINDS
an existing row from a prior failed send — only on a genuine insert — so
`#create` re-enqueues those failed rows explicitly (`sendable?` accepts
failed rows). Pending, sending, and sent rows are deliberately left alone,
so a repeat POST never double-sends.

## Why `LegislatorEmailText` builds the wording on the server

`LegislatorEmailText` is the one place the "email your legislator" wording
is written. `UserLegislatorEmailMailer` drops these strings into the
outgoing email, and `BillsController#show` hands the SAME strings to the
page as the `email_preview` prop, so the compose window shows EXACTLY
what the mailer will actually send. An older version of the UI kept its
own copy of this wording in the browser, and the two copies slowly
stopped matching each other; building the text once, on the server,
removes that risk entirely.

`LegislatorEmailText` also works on a `UserLegislatorEmail` that was NEVER
saved: the preview on the bill page builds one in memory (with
`user_legislator:` and `bill:` set directly) and never writes it to the
database. Every method reads through the linked records rather than the
email row's own columns, so nothing here depends on the row having an id.

`#user_full_name` falls back to the placeholder `"{YOUR NAME}"` only in
the preview — the send endpoint refuses to run unless the user has a full
name, so a real outgoing email can never carry that placeholder.

## Browser coverage for the modal (spec/system/email_legislators_spec.rb)

The rebuilt "email your legislator" modal moves through four steps and had
only request and model tests until this spec: the button that appears once
a user has voted, the message preview, verifying the address with a code
Twilio emails, sending, and the per-legislator status list. The button
renders only for a user who has voted, so every example creates a vote
first with the `:user_vote` factory.

`build_voter` sets `is_registration_complete`, `registration_status`, and
`is_email_verified` with `update!` AFTER the user record already exists,
because `User#before_create` forces `is_registration_complete` and
`is_email_verified` back to their defaults on create — setting them in the
`create(:user)` call itself would be silently overwritten.

The preview text is asked for through the page (`have_css`, scoped by the
surrounding `within`) rather than by holding onto a found element: the
modal can re-render between the find and the read, and a held element then
fails as "stale element reference". `have_css` asks again on
every retry, so a re-render mid-check does not fail the example.
