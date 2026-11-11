---
mode: explanation
summary: "Why the admin guard runs before set_bill in BillOfTheWeekScheduleController, and why its tab redirect default is the Schedule tab"
status: agent-extracted
related: [docs/explanation/bill-creator-tab-url-routing.md]
---

# Bill of the Week schedule: admin guard order and tab redirect default

Only sway admins may change the schedule. `verify_is_sway_admin` has to run
before `set_bill`, so a non-admin request never reaches the `Bill.find`
lookup.

`spec/requests/admin_bill_of_the_week_schedule_spec.rb` is a companion to
`spec/requests/bill_of_the_week_schedule_spec.rb`, which covers the
success and failure paths of `PUT /update` through the shared `Setup`
context. This file hits the same controller as an admin instead, so the
admin-gate assertions live separately from the ordinary happy/unhappy-path
coverage.

The table mapping tab names to route helpers, plus the logic that decides
which tab to send the user back to, live in the shared
`BillCreatorTabRedirects` concern (`OrganizationsController` uses it too —
see `docs/explanation/bill-creator-tab-url-routing.md`). A tab name this
controller does not recognize falls back to the Schedule tab, which is where
this form lives.

## Why the GET route to `#update` is pinned as removed

A stray `get "bill_of_the_week_schedule/update"` route let `#update`, which
changes data, be triggered by a plain GET. GET requests skip the
cross-site request forgery check, and a `SameSite=Lax` session cookie is
still sent when the browser navigates to a link, so any link a signed-in
admin clicked could have fired it. That route is gone; only the RESTful
PUT/PATCH member route (`resources ... only: %i[update]`) is left.
`spec/routing/bill_of_the_week_schedule_routing_spec.rb` pins the GET route
as removed so it cannot come back.
