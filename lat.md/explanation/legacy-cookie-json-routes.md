---
lat:
  mode: explanation
---

# Legacy cookie-session JSON routes

The top-level JSON routes remain available for existing consumers while bearer API routes expose the same controller families under `/api`.

## Cookie-session JSON routes share controllers with bearer API twins

The top-level score, district, influence, legislator, and locale JSON routes preserve compatibility for external and organization consumers; the corresponding API routes remain available under the `api` scope in [[config/routes.rb]].

Keeping these routes does not make browser pages depend on them: web pages receive Inertia props, while mobile account identity is governed by [[identity-and-access#Identity and access#Sessions, cookies and bearer tokens]]. The general dual-format surface is listed in [[surfaces#Delivery surfaces#Dual-rendered JSON]].

## Retired top-level read routes and numeric user destroy constraint

[[config/routes.rb]] restricts top-level `legislator_votes` to `:create`, omits the duplicate `user_districts` and `user_legislator_scores` controllers, and constrains `DELETE /users/:id` to numeric IDs (`id: /\d+/`).

The former top-level `GET /legislator_votes` endpoints were unreachable orphans superseded by Inertia props and `/api/legislator_votes`, while the numeric `:id` constraint on `resources :users, only: %i[destroy]` prevents the self-deletion route used by the mobile `DeleteAccountScreen` from shadowing named routes under `namespace :users`.
