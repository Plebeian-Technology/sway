---
lat:
  mode: explanation
---

# Detecting an unreviewed AI summary on an organization position

`OrganizationBillPosition#summary_ai_unreviewed?` is true when this position's text is a machine's words nobody has revised. The bill page renders a notice for it.

## The test

`ai_summary` holds the model's original words.

Approving a position copies them into `summary`. Any later edit changes `summary` but not `ai_summary`, so the two values differ and the method reads false — there is no separate flag to remember to clear. A `NULL` `ai_summary` means no machine ever wrote this text, so the method also reads false.

## Approving is not revising

`ApproveOrgPositionService` stores no `ai_summary` for a draft a person already edited before approval, so a summary that was rewritten before approval gets no notice.

`ApproveOrgPositionService` stores no `ai_summary` for a draft a person already edited before approval, so a summary that was rewritten before approval gets no notice — the same "approving is not revising" rule the `Bill` model's equivalent flag follows (see `bill-summary-ai-unreviewed-detection.md`).

## A member's approved change clears ai_summary

[[app/services/approve_position_change_service.rb#ApprovePositionChangeService]] sets `ai_summary` to `nil` when it approves a change.

The organization's members reviewed the text, and a support-only change keeps the summary word for word, so leaving `ai_summary` in place would show "Generated using AI, not yet reviewed" beside the organization's own byline.

## Where the flag surfaces

Surfaces and serializers exposing the `ai_summary` indicator to distinguish automated position drafts from verified human submissions.

- `#to_builder` includes only the boolean flag, never `ai_summary` itself —
  putting the model's original text on a public page beside the text that
  replaced it would defeat the point of the notice.
- `#to_public_json` adds the flag by hand rather than through `PUBLIC_FIELDS`,
  because that field's loop calls `public_send` on a column name; the flag is
  a predicate method, not a column, so adding it to `PUBLIC_FIELDS` would
  make `respond_to?` return false and silently drop the notice.
- `Organizations::BaseController#membership_as_props` hand-builds the
  position hash it sends to the organization member pages, rather than
  serializing through a resource. Because that hash is hand-built, it is
  the one place `summary_ai_unreviewed` has to be added by hand — leaving
  it out means this screen alone shows the summary text with no notice,
  even though every other surface carries the flag.

## What PUBLIC_FIELDS is, and the rule around it

`OrganizationBillPosition::PUBLIC_FIELDS` is the explicit allow-list of fields the non-admin `Public::OrganizationsController#show` may expose.

`#to_public_json` reads only from this list, by calling `public_send` on each column name it names — the record's raw `as_json` must NEVER be called from a public surface, since that would expose every column, including ones this allow-list deliberately leaves out. The regression that would catch a future violation of that rule is `spec/models/organization_public_json_spec.rb`.

## Why OrganizationBillPositionResource mirrors PUBLIC_FIELDS

`OrganizationBillPositionResource` hands out only the fields that match the model's `PUBLIC_FIELDS` (behind `to_public_json`), which is what the mobile org detail screen expects.

The plain Rails `as_json` this replaced also gave away `updated_at`.

The Bill page's nested version still goes through the model's `to_builder`, embedding the whole organization instead of `organization_id`. That shape moves over to this resource when convenient, not as part of this change.

## The frontend type mirror (app/frontend/index.d.ts)

`IOrganizationPosition.summary_ai_unreviewed`: True when the summary above is a machine's words that no person has revised.

Every server route that sends a position sends it, so no screen is left showing the text with no notice. That is a rule the key-set request specs hold down, not a list kept here — a list of writers in a comment goes stale without anything noticing.
