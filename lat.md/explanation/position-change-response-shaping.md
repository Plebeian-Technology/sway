---
lat:
  mode: explanation
---

# Organizations::PositionChangesController response design

Why Organizations::PositionChangesController splits its approve/reject responses by mobile_api_request?

## Why the message constant exists

`ALREADY_FINALIZED_MESSAGE` spells the "already finalized" refusal in one place, so the controller and its tests cannot drift apart.

It is deliberately not translated yet; when translations arrive, only this line changes instead of three separate copies.

## Where the real work happens

The real work — re-reading the row inside a transaction, refusing a change that was already decided, and updating both the change and the position.

The real work — re-reading the row inside a transaction, refusing a change that was already decided, and updating both the change and the position — happens in `ApprovePositionChangeService` (for `#update`) and `RejectPositionChangeService` (for `#destroy`), which also document the rules that keep two admins clicking at the same moment from colliding. These controller actions only handle HTTP: turning the service's answer into the right response for the caller.

## Why approval uses PUT/PATCH and rejection uses DELETE

Two callers arrive at `#update` with different verbs: the website sends PUT with no body, the mobile app sends PATCH with `{ status: "approved" }`.

The body is ignored either way — approval is implied by the request itself, and only an active org admin gets this far. `#destroy` uses DELETE for rejection on purpose: rejecting takes something away, approving adds to it. The verb is DELETE, but nothing is actually deleted: the row stays as the audit trail, with its status set to rejected and the rejecting admin and the time recorded.

## Why the mobile/web response split is hand-written instead of redirect_or_json

Both `#update` and `#destroy` split on `mobile_api_request?` by hand instead of using `redirect_or_json`, for three reasons:

1. The mobile app's 422 body must be `{ error: ... }` rather than
   `{ redirect, flash }`. The app reads the message out of
   `error.message`, so a flash body would show up as a bare "HTTP 422"
   instead of the actual reason.
2. The web 422 branch needs `flash[:alert]`, which `redirect_or_json`
   cannot produce — it only sets `flash[:notice]`.
3. Mobile success needs a genuine 204 with no body — without that split, a
   mobile PATCH/DELETE that landed on a redirect would send the app a web
   page URL it cannot read.

`mobile_api_request?` is true for bearer-token auth OR an `Accept: application/json` header (see `app/controllers/concerns/mobile_format_negotiation.rb`). So a cookie session that asks for JSON takes the JSON branch too — intended, though neither real client does that today.

`respond_already_finalized` is the shared "this change was already decided" reply, used by both `#update` and `#destroy`, following the same split: mobile gets a 422 with `{ error: <message> }`; the website gets a flash warning and a redirect back to the caller's membership page.

## Why the rejection audit log line exists and logs named fields

The rejected row is kept, but nothing else in the app shows that a rejection happened — no screen, no notification, no queue.

The log line in `#destroy` is the record of last resort, so anyone later asking "who rejected change X?" can find an answer in the production logs.

It logs `organization.id` — the id the base controller already looked up and checked — rather than the raw URL parameter. A newline pasted into that parameter could otherwise fake a whole extra log line and mislead whoever is reading. Logging named fields (`change_id`, `rejected_by_user_id`, `organization_id`) instead of one long string also lets log tools search by those fields directly.

## Why the finalized-state rule is written once, in shared test helpers

`spec/requests/organizations/position_changes_controller_spec.rb`'s helpers that put a row into its approved or rejected state are pulled into shared methods, so the rule for what counts as finalized.

`spec/requests/organizations/position_changes_controller_spec.rb`'s helpers that put a row into its approved or rejected state are pulled into shared methods, so the rule for what counts as finalized — `rejected_by` plus `rejected_at` plus `status`, or `approved_by` plus `status` — is written once rather than once per example.

`spec/requests/organizations/position_changes_controller_spec.rb`'s `sign_in` is the shared `RequestSpecSessionHelpers#sign_in` from `rails_helper.rb` — this file does not define its own.

## Why ApprovePositionChangeService and RejectPositionChangeService re-read the row under a lock

Both services re-read `OrganizationBillPositionChange` with `.lock` INSIDE their own transaction (`OrganizationBillPositionChange.lock.find(@change.id)`) rather than trusting the row the controller already loaded.

Both services re-read `OrganizationBillPositionChange` with `.lock` INSIDE their own transaction (`OrganizationBillPositionChange.lock.find(@change.id)`) rather than trusting the row the controller already loaded, and both check `#finalized?` again on that freshly-locked copy before writing anything. Together — one lock, taken by whichever request gets there first, and a re-check of a value that could have changed since the controller's original read — this is what keeps an approve and a reject arriving at the same moment from both succeeding: whichever request's transaction takes the row lock first commits and finalizes the change, and the second request's re-check of `#finalized?` inside its OWN transaction sees the already-finalized row and returns `:already_finalized` instead of writing a second, contradictory outcome. On SQLite (this app's database), the row stays locked through the writes for the same reason `config/database.yml`'s `default_transaction_mode: IMMEDIATE` makes the lock in `ApproveOrgPositionService#delete_approved_draft` authoritative — see [[docs/explanation/org-position-approval-guard-chain.md|the approval guard chain doc]].

`ApprovePositionChangeService#call` uses `ActiveRecord::Rollback` (not an exception) to back out of the transaction on `:already_finalized` or `:approve_failed` — both are expected, gentle outcomes the caller is meant to branch on, not failures that should propagate as an exception. `RejectPositionChangeService` does the same for `:already_finalized`, its only gentle outcome; anything else it raises, because there is no separate error list to report through — the caller of `#call` maps a raised exception, not a returned symbol, to any harder failure.
