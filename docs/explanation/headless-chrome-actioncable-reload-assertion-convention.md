---
mode: explanation
summary: "Why system specs avoid asserting on the exact moment an ActionCable push triggers an Inertia reload in headless Chrome, and the workaround convention used instead."
status: agent-extracted
related: []
---

<!-- vale Vale.Spelling = NO -->

# Why system specs don't assert on live ActionCable+Inertia reload timing

Asserting on the exact moment a WebSocket push arrives and Inertia refetches
props is known to be unreliable in headless Chrome in this codebase.
`spec/system/user_voting_spec.rb` dodges it by stubbing
`ActionCable.server.broadcast` outright, and
`spec/system/admin/creator/pipeline_stage_selection_spec.rb` has a pending
example for the same reason — it does not capture the Inertia reload +
ActionCable push timing under headless Chrome reliably.

`spec/system/legislator_reassignment_spec.rb` follows a third convention:
the reassignment happens on the server with no user action — that is the
claim being tested — and then the page is visited again and checked. That
the broadcast is sent at all, which is what lets the page update itself
live, is pinned separately with `have_broadcasted_to` in
`spec/services/reconcile_user_districts_service_spec.rb`. So the live-timing
assertion is split off into a service spec, and the browser spec only
checks the end state after a fresh visit.

## Related test setup conventions

`legislator_reassignment_spec.rb` also runs on the macOS host, using the
chromedriver Selenium fetches for itself, rather than inside Docker — the
same convention as `spec/system/legislators_navigation_spec.rb`. And it uses
the congress locale with a stubbed `Census::Congress#request`, the same
no-network setup as `spec/services/sway_registration_spec.rb` and
`spec/services/reconcile_user_districts_service_spec.rb`: everything else
runs for real (`ReconcileUserDistrictsJob` calls
`ReconcileUserDistrictsService`, which calls
`SwayRegistrationService#district_legislators`), only the Census HTTP call
is faked.
