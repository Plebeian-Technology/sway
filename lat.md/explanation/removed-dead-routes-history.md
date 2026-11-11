---
lat:
  mode: explanation
---

# Why removed_dead_routes_spec.rb pins these routes as gone

Some routes were only ever called from the since-deleted V1 tree, and others had no reachable callers at all.

Those routes and their controllers were deleted. This spec pins them as gone so a later change cannot quietly bring back an endpoint nothing uses and nothing tests.

`be_routable` and `route_to` are routing matchers from rspec-rails. Their type signatures live in `sig-test/rspec_dsl.rbs`, so the Steep type checker understands them without a suppression comment on every line.

## The old email and user-detail endpoints

The feature was rebuilt on new routes: `POST /user_legislator_emails` came back as a plural RESTful controller, called from the modal on the bill page, and email verification moved under `/users/email_verification`.

Only the old top-level `/email_verification` and `/users/details` shapes stay pinned as dead.

## The JSON GET endpoints nobody owned

`UserDistricts#index` was a word-for-word copy of `Districts#index`.

Nothing called `UserLegislatorScores`. `legislator_votes#show` read `params[:bill_id]`, which `GET /legislator_votes/:id` never sends, so it always returned an empty list.

The remaining top-level read routes that have a twin under `scope "api"` were left in place for now: those top-level routes serve anonymous and cookie callers, while the `/api` twins require an API key, so deleting them would take a capability away. That is tracked separately.
