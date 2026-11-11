---
lat:
  mode: explanation
---

# Request locale selection

The request may name a locale, but only an existing locale can become the reader's remembered choice.

## A query locale is validated before the cookie is written

`sway_locale_id` in the query string is a write to the long-lived locale cookie. [[app/controllers/application_controller.rb#ApplicationController#set_sway_locale_id_in_session]] leaves the existing cookie untouched when the id has no row and tells the reader which locale remains active.

## The query locale wins over the cookie on reads

[[app/controllers/application_controller.rb#ApplicationController#find_current_sway_locale]] checks the request parameter before the cookie. Mobile requests carry the id in the query string because bearer clients do not use the web locale cookie.

## One request reuses its locale lookup

Both the cookie write and the current-locale read need the same lookup result. [[app/controllers/application_controller.rb#ApplicationController#requested_sway_locale]] memoizes that result so a request carrying `sway_locale_id` does not query the row twice.

When `sway_locale_id` is absent, [[app/controllers/application_controller.rb#ApplicationController#requested_sway_locale]] memoizes `nil` without querying `sway_locales`. Neither the request lookup nor the cookie and fallback lookups preload all `:districts` rows on every request; when `:districts` is not already loaded, [[app/models/sway_locale.rb#SwayLocale#at_large_district]] queries and memoizes only the zero-numbered district.

## A stale locale cookie is removed

The read path removes a cookie whose locale row was deleted before falling back to the user's default or the application default. Otherwise a dead twenty-year cookie would be reconsidered on every request.

## Why SwayLocalesController#show falls back with find_by and never sets a cookie

[[app/controllers/sway_locales_controller.rb#SwayLocalesController#show]] looks up the requested [[app/models/sway_locale.rb#SwayLocale]] with `find_by` so an unknown identifier falls back to `SwayLocale.default_locale` without raising a not-found error or mutating session cookies.

Locale inspection via `GET /sway_locales/:id` is a read-only lookup, whereas active locale selection happens through query parameters or the session locale switch endpoint.

## Default locale selection prefers declared jurisdictions

[[app/models/user.rb#User#default_sway_locale]] selects a declared non-Congress locale first, then declared Congress, before falling back to undeclared locales.

When a registered user signs up from an unsupported municipal jurisdiction, registration auto-creates locale records for demand tracking. Selecting a declared locale first ensures user views default to populated legislative data instead of empty municipal shells.

## Anonymous fallback locale lists are filtered to declared locales

Public and anonymous locale discovery endpoints fall back to [[app/models/sway_locale.rb#SwayLocale|SwayLocale.declared]] rather than every persisted [[app/models/sway_locale.rb#SwayLocale]] row.

When unsupported registrations auto-create municipal locale records, exposing undeclared rows in public pickers, mobile bootstrap, and sitemaps produces empty legislative shells for visitors. Filtering anonymous fallbacks to declared locales restricts public discovery to supported jurisdictions while authenticated users continue receiving their assigned locales.
