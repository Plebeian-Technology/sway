---
lat:
  mode: explanation
---

# Design notes on Bill's JSON payload

`Bill#render` builds the props the single-bill Inertia page receives, and `Bill#to_builder` builds the nested Bill JSON several surfaces share.

This document collects several small, independent design choices behind both that don't belong to any single existing doc.

## Every render() prop is a lambda

Each value `Bill#render` returns is wrapped in a lambda rather than computed eagerly, so a partial reload (`only: ["bill_score", ...]`) runs only the lambdas for the keys it actually asked for.

Each value `Bill#render` returns is wrapped in a lambda rather than computed eagerly, so a partial reload (`only: ["bill_score", ...]`) runs only the lambdas for the keys it actually asked for — the `legislators` list alone is roughly 540 records for Congress, and building it on every reload regardless of which keys were requested would waste that query on every partial reload that didn't ask for it.

`inertia_rails` and the mobile JSON path (`MobileFormatNegotiation#resolve_inertia_props`) both invoke these lambdas in the calling controller's context rather than the model's, so `self` (the `Bill` instance) has to be captured into a local (`bill = self`) before the lambdas are defined — inside the lambda body, `self` would otherwise resolve to the controller.

## user_vote goes through UserVoteResource, not the raw record

`user_vote` used to hand back the raw `UserVote` record.

That dumped every column, including `user_id` and both timestamps, when the only field any reader uses is `support`. It now goes through `UserVoteResource`, which names exactly that one field.

## Why categories uses .map(&:name), not .pluck(:name)

`Bill#to_builder` reads `categories.select(&:active?).map(&:name)` rather than `.pluck(:name)`.

`pluck` always issues a fresh `SELECT`, which would bypass `BillsController#index`'s `.includes(:categories)` preload and add a query per bill on the index page. Filtering to `active?` happens in memory, against the already-loaded association, for the same reason: a database-side filter can't reuse a preload that already ran without the filter, and a switched-off category would otherwise stay off the active filter chips while still rendering on the bill card — the two would disagree about which categories exist.

## vote_date_time_utc is public so callers don't re-derive the rule

`Bill#vote_date_time_utc`.

`Bill#vote_date_time_utc` — the earlier chamber's vote date when both chambers voted, whichever one voted when only one did, `nil` when neither has — is a public method so any caller that needs to place a bill's vote in time can call it, rather than re-deriving the house/senate comparison itself. `TermYearFromVotes` is one such caller.

## summary_ai_unreviewed ships as a flag, not a rendered string

`Bill#to_builder` sends `summary_ai_unreviewed` as the boolean flag from `#summary_ai_unreviewed?` (see [[docs/explanation/bill-summary-ai-unreviewed-detection.md|Detecting an unreviewed AI summary]] for how that flag is computed), never a pre-rendered notice string.

Every reader — the web bill page, the mobile app, the JSON API — builds its own sentence from the flag. A stored string would have to be invalidated by every writer that changes `summary`, and a writer that forgets leaves a stale notice on text a person already reviewed.

## SUMMARY_PLACEHOLDER is a shared constant, not a repeated literal

`Bill::SUMMARY_PLACEHOLDER` ("Summary pending") is what `LegislationIngestionService` writes to `summary` for a bill with none.

It is a constant, rather than a string typed out in both places, because `BillSummaryPublication` also reads it, to tell a not-yet-published bill apart from one nobody has summarized yet — two hand-typed copies of the same sentinel string is how the two readings would silently drift apart.

## The frontend type mirror carries the same flag on both bill shapes

`app/frontend/index.d.ts`'s `IApiBill.summary_ai_unreviewed`: True when the summary above is a machine's words that no person has revised, so the bill page shows a notice under it.

The sentence itself is NEVER in `summary` — every reader of that column would inherit it, and revising the text would leave it attached to something it no longer describes.

`IBill.summary_ai_unreviewed`: True when the summary above is a machine's words that no person has revised, so the bill page shows a notice under it. Both this and `IApiBill` carry it because both are `Bill#to_builder`'s output; one of the two missing it is how a screen ends up rendering the text with no notice.

`IBillOrganizationPosition`: What `OrganizationBillPosition#to_builder` sends: one organization's summarized stance on ONE bill, with the organization tucked inside. `Bill#render` sends an array of these as the `organizations` prop, holding only that bill's active positions. The mobile app's `OrgPositionsSection` reads the same flat shape.

## The category column stays, unused

`category`, the old single-subject field, is no longer required and has been dropped from the admin bill form and every public screen in favor of the newer list of categories (`bill_categories`).

The column itself stays, still `NOT NULL` with a database default of `""`, so older readers and serializers that still reference it keep working; nothing collects or displays its value any more.
