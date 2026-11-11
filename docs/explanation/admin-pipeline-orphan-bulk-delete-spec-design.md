---
mode: explanation
summary: "Why spec/system/admin_pipeline_orphan_bulk_delete_spec.rb exists as a browser spec on top of the request spec, and the two Capybara-specific waits it relies on."
status: agent-extracted
related: []
---

<!-- vale Vale.Spelling = NO -->

# spec/system/admin_pipeline_orphan_bulk_delete_spec.rb design notes

## Why this browser spec exists

The bulk delete of orphan runs — a "Delete N orphan run(s)" button that
only appears when `orphan_pipeline_run_count` is above zero, a React
confirmation dialog, a permanent delete plus an activity-log entry and a
flash message, and the button disappearing once it succeeds — is fully
covered by request specs in
`spec/requests/pipeline_runs_orphan_bulk_delete_spec.rb`, but had never
been driven in a browser; it was checked by hand once, on a seeded run.
This spec runs the whole loop: browser, server, flash message, partial
reload.

## Forcing orphan? to true in the test database

Asking whether a run is an orphan normally means looking in Solid Queue's
job table for a live job that still refers to that run id. In the test
database `SolidQueue::Job` is empty, and the lookup can raise, in which
case the answer defaults to true. The spec forces `orphan?` to `true` for
every run so the seeded rows count as orphans whatever state Solid Queue
is in, rather than depending on that raise-and-default path.

## Confirming through the app's own dialog, not window.confirm

The delete button asks for confirmation through the app's own React dialog
(`ConfirmProvider` / `useConfirm`), not the browser's `window.confirm`.
Capybara's `accept_confirm`/`dismiss_confirm` can only drive real browser
dialogs, so the spec confirms or cancels by clicking the dialog's own
buttons instead.

## Waiting for the button to disappear before checking the database

The delete round trip is quick enough that the progress bar — and
therefore `wait_until_loaded` — can race the server's delete loop and
leave the count check reading halfway through. The button disappearing is
the visible signal that the orphan count dropped to zero and the controls
redrew through a partial reload, so the spec waits for that absence before
reading `LegislationPipelineRun` directly.
