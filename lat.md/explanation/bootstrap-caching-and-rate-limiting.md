---
lat:
  mode: explanation
---

# Bootstrap caching and rate limiting

[[app/controllers/api/v1/bootstrap_controller.rb#BootstrapController|The bootstrap controller]] rate-limits and caches mobile launch payloads to protect backend databases while ensuring immediate personalized consistency.

## Why locale and featured bill are cached per locale

Locale and featured bill responses are cached in `Rails.cache` for 60 seconds, keyed per locale, to absorb the stampede of requests when many phones launch the app at once.

The cache key `api_v1_bootstrap:botm:#{locale.id}` stores the shared serialized bill representation without user-specific voting state.

While the 60-second time-to-live bounds natural cache lifetime, administrative mutations to featured schedules, bill content, or bill records explicitly evict `api_v1_bootstrap:botm:#{sway_locale_id}` via [[app/controllers/api/v1/bootstrap_controller.rb#BootstrapController#expire_botm_cache|expire_botm_cache]] to prevent clients from observing stale featured bills.

Eviction is placed in controller actions (`BillOfTheMonthScheduleController#update`, `BillsController#create`, `BillsController#update`, `BillsController#destroy`, `BillsController#paste_summary`, and `BillsController#restore_summary_revision`) rather than model callbacks (`after_commit`). ActiveRecord callbacks fire during batch ingestion, seeds, and background pipeline runs where cache clearing is redundant or causes unnecessary cache churn. Binding eviction to operator controller actions guarantees that when an administrator reschedules, edits, or deletes a bill, mobile clients immediately receive the updated featured bill on their next bootstrap request without waiting for the 60-second TTL to lapse.

## Why cached bills are checked for visibility

A cached serialized bill can outlive its visibility in ordinary queries, so [[app/controllers/api/v1/bootstrap_controller.rb#BootstrapController#show|bootstrap]] checks the cached identity in the requested locale before merging a vote.

[[bill-session-archiving#Bill session archiving#Active views|Session archiving]] hides retained bills through the normal scope. A hidden cached fallback therefore triggers fresh featured-bill selection and replaces the shared cache with a visible same-locale bill or nil. Both featured-bill keys receive that result immediately, within the original cache lifetime; retained votes never make an archived payload visible again. Other locales' cache entries remain independent.

## Why the rate limit exists

A rate limit of 60 requests per minute per IP throttles abusive scraping of the bootstrap endpoint without hindering genuine application launches.

The limit protects database capacity during launch spikes and automated crawling attempts.

## Why the featured bill vote is merged in after the cache fetch

The current user's vote is merged into the bootstrap response after reading the cached featured bill payload rather than baking it into the shared cache.

Caching personalized votes in a shared entry would either leak voting state across users or cause immediate vote updates to be masked by stale cache entries.

## Why the user address has an explicit payload

[[app/controllers/api/v1/bootstrap_controller.rb#BootstrapController#current_user_payload|The mobile user payload]] serializes the address through [[app/models/address.rb#Address#to_builder|its explicit public representation]].

The raw address attributes include precise home coordinates and an extra street field that the shared web payload excludes. Reusing the explicit representation keeps those coordinates server-side and gives mobile the same address shape as the shared web user prop.

## Why the feature flags cache key carries an explicit version segment

The feature flags cache key uses an environment and version suffix to ensure explicit cache invalidation when feature flag definitions evolve.

The versioned key isolates environment-specific configuration and accommodates schema evolutions without manual cache flushing.

## Why the locale list has its own longer TTL

Supported jurisdictions are cached for 300 seconds under a versioned key because locale definitions change infrequently compared to active legislation.

This longer lifetime reduces repeated queries across concurrent launches while allowing explicit key invalidation when locale configurations are updated.

## Why show is a single request

The bootstrap endpoint consolidates user identity, active locale, featured legislation, feature flags, and client version bounds into a single network round-trip.

This single-request design prevents cascading network waterfalls during cold application launches. The envelope delivers the `bill_of_the_month` payload (or `nil` when no bill is featured in the locale) so clients need no extra round-trips.
