---
mode: reference
summary: "Documents the response codes BillsController#paste_summary returns for each outcome PasteSummaryService reports."
status: agent-extracted
related: []
---

# paste_summary response outcomes

`PasteSummaryService` parses, validates, and persists a pasted summary JSON
body, and writes the activity-log events for that work.
`BillsController#paste_summary` maps the service's outcome to a response:

| Outcome | Status | Response |
|---|---|---|
| `:persisted` | 200 | Mobile: JSON bill payload. Web: flash notice + redirect. |
| `:persisted_unsettled` | 200 | Same as `:persisted`, plus a flash alert. |
| Any other value | 422 | `render_paste_summary_errors` — mobile gets a structured error array, web gets `flash[:paste_summary_errors]`. |

## Why a redirect alone can't distinguish acceptance from refusal on the web path

On the web, both an accepted paste and a refused one redirect back to the
Bill Creator — `have_http_status(:redirect)` on its own proves nothing.
What separates them is which flash key comes back: an accepted paste sets
`flash[:paste_summary]` and stores the new summary; a refused paste sets
`flash[:paste_summary_errors]` instead and leaves the stored summary
untouched.

## Why :persisted_unsettled is still a 200

`:persisted_unsettled` means the summary body and its audit entry saved, but
the bill's status could not move. The save is real work — returning an error
status would make the screen show a red "Failed" over text that was, in
fact, just saved.

Instead the controller sets a flash alert telling the operator to paste the
summary again to finish. The alert rides the ordinary flash slot. Mobile's
200 response is unaffected either way, because mobile reads
`generation_status` fresh from the bill rather than trusting the outcome
symbol.

## The frontend IValidationError type

`IValidationError` (`app/frontend/types/bill_creator.ts`) is the shape of
one validation error from `/bills/:id/paste_summary` when it answers 422,
the "your input was rejected" status. `path` is a JSON Pointer — a
slash-separated path into the submitted data, such as
`/draft_org_positions/0/stance` — and `message` is the plain-English
reason, shown right under the text box. It matches the body Rails builds
in `render_paste_summary_errors` for the mobile JSON response. On the web,
Inertia flattens these into its usual errors object, keyed by those same
JSON Pointer paths.

## PasteSummaryDialog's test setup

The dialog no longer passes errorBag or onError — the controller sends rejection errors only
through `flash[:paste_summary_errors]`.
