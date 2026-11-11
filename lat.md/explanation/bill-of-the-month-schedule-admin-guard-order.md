---
lat:
  mode: explanation
---

# Bill of the Month schedule: admin guard order and tab redirect default

Only sway admins may change the schedule. `verify_is_sway_admin` runs before `set_bill` so unauthorized requests never reach the `Bill.find` lookup.

`spec/requests/admin_bill_of_the_month_schedule_spec.rb` is a companion to `spec/requests/bill_of_the_month_schedule_spec.rb`, which covers the success and failure paths of `PUT /update` through the shared `Setup` context. This file hits the same controller as an admin instead, keeping admin-gate assertions separate from ordinary happy/unhappy-path coverage. Non-admin requests for nonexistent IDs receive a 302 redirect rather than 404, preventing information leakage about bill existence.

The table mapping tab names to route helpers, plus the logic deciding which tab to return the user to, live in the shared `BillCreatorTabRedirects` concern. A tab name this controller does not recognize falls back to the Schedule tab, which is where this form lives.

## Why the GET route to `update` is pinned as removed

A stray GET route to `#update` would permit state mutation via GET requests, which skip cross-site request forgery checks.

`spec/routing/bill_of_the_month_schedule_routing_spec.rb` pins GET routes as unroutable so data mutations remain restricted to RESTful PUT and PATCH member routes.

## Envelope parameter extraction

The controller extracts scheduling parameters from the `:bill_of_the_month_schedule` envelope.

Unenveloped payloads fall back to top-level parameters, permitting `:bill_id`, `:scheduled_release_date_utc`, and `:tab_key`.

## Client form submission and date transformation

The admin bill scheduling form converts dates to calendar day strings before submitting to the canonical monthly route.

`BillSchedule.tsx` calls `router.put("/bill_of_the_month_schedule/0", ...)` with `dateToCalendarDay` to submit a `YYYY-MM-DD` calendar day, avoiding timezone day shifts across UTC boundaries. Setting an empty release date unschedules the bill, returning it to draft state, while choosing a future date queues the bill for monthly publication and automated notifications.

## Admin controller allowlist enforcement

The admin gate lint check ensures every admin-accessible controller declares the admin verification before_action.

`lib/tasks/sway_lint.rake` and `CLAUDE.md` register `BillOfTheMonthScheduleController` in the authoritative list of admin-gated controllers. The allowlist names the one controller that serves the schedule routes.
