---
lat:
  mode: explanation
---

# Why an empty Bill of the Month stays on the page

A locale with no featured bill renders the page with no bill rather than redirecting to the bill list, so the reader stays on the page and can select another locale.

`BillOfTheMonthController#index` renders the page with no bill instead of bouncing the reader to the bill list. That design allows the locale picker to remain interactive on screen so the reader can switch locales without an unexpected jump.

## Legacy route preservation and query parameter carry

Every request to the retired `/bill_of_the_week` and `/api/bill_of_the_week` paths receives a 301 redirect to the matching `bill_of_the_month` path, carrying the query parameters.

The two redirect routes in `config/routes.rb` use `redirect(path:)`, so Rails re-encodes the parsed query string. A malformed query string answers 400 instead of raising. The query may come back reordered (`sort=newest&sway_locale_id=2`), which is equivalent. The redirect applies to Inertia, JSON and bearer-token requests too; clients that follow redirects reach the canonical route, and old SMS and shared links keep working. No controller serves the retired name.

## Universal link and native associated domain paths

Associated domain files preserve native app deep linking for both canonical and legacy reader addresses.

`WellKnownController#apple_app_site_association` lists `/bill_of_the_month` and the retired `/bill_of_the_week` in its universal links path components. Supporting both paths ensures shared links and legacy shortcuts open natively in the mobile app without requiring an intermediary browser redirect.

## Bootstrap payload key and null precedence

The mobile bootstrap contract serves only the canonical `bill_of_the_month` key.

`Api::V1::BootstrapController` serializes the featured bill under `bill_of_the_month` from the shared `api_v1_bootstrap:botm:#{locale&.id}` cache. The retired name `bill_of_the_week` is not sent. When no legislation is featured, `null` is explicitly returned for `bill_of_the_month` so client caching logic does not fall back to stale records.

## Why the empty-state copy names the jurisdiction

`PARITY_COPY.billOfTheMonth.noneForLocale` names the selected jurisdiction so an empty screen explains why no legislation is featured rather than appearing broken.

The page remains in place when switching locales, so naming the jurisdiction clarifies that no bill is currently featured for that specific place.
