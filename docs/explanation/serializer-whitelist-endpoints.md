---
mode: explanation
summary: "Why several controllers serialize through a whitelist resource instead of dumping ActiveRecord records to JSON directly -- raw as_json would expose every column, including user_id and timestamps."
status: agent-extracted
related: []
---

<!-- vale Vale.Spelling = NO -->

# Why these endpoints serialize through a whitelist resource

`OrganizationBillPositionsController`, `UserLegislatorsController`, and
`UserVotesController` all serialize their JSON responses through a
whitelist resource (`OrganizationBillPositionResource`, a legislator
resource, `UserVoteResource`) rather than dumping the ActiveRecord record
straight to JSON.

Rendering a raw record — `uv.to_json`, `.attributes`, or default `as_json`
— used to dump every column, which leaked `user_id` and timestamps
(`created_at`/`updated_at`) that callers were never meant to see. The
resource names exactly the public fields, so a column added to the table
later does not silently become part of the public response.

For `OrganizationBillPositionsController#show`, a missing position still
answers with a `null` body, as it always has — only a row that exists goes
through the resource.

## `BillsController` follows the same rule

`BillsController#index` serializes each bill's `user_vote` through
`UserVoteResource` rather than dumping the raw `UserVote` record — the raw
record used to put every `user_votes` column into the prop.
`BillsController#show` serializes the `?with=legislator` payload through
`LegislatorResource` for the same reason, not the raw ActiveRecord record.

## Why `DistrictResource`'s field list matches the old to_builder and raw index shapes

`DistrictResource` hands out the public shape `District#to_builder`
already sends (`name`, plus `number` and `region_code`, which the model
works out rather than storing), plus the `id` and `sway_locale_id` that
the old raw `districts#index` payload carried. Timestamps are
left out on purpose.
