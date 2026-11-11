---
mode: explanation
summary: "Why Api::V1::BootstrapController rate-limits and caches the way it does: per-IP scraping defense, per-locale Bill of the Week caching order, and the versioned cache keys for feature flags and locales."
status: agent-extracted
related: [docs/explanation/mobile-bootstrap-lifecycle.md]
---

<!-- vale Vale.Spelling = NO -->

# `Api::V1::BootstrapController` caching and rate limiting

## Why locale and Bill of the Week are cached per locale

Locale and Bill of the Week responses are cached in `Rails.cache` for 60
seconds, keyed per locale, to absorb the stampede of requests when many
phones launch the app at once.

## Why the rate limit exists

60 requests per minute per IP is a partial defense: it throttles anyone
scraping the bootstrap payload to map out the API, without meaningfully
limiting a real client's normal launch traffic.

## Why the Bill of the Week vote is merged in after the cache fetch

`botw_json` is cached per-locale. The current user's vote is
merged in AFTER the cache fetch, not baked into the cached payload — caching
the vote too would mean a refetch right after voting shows `user_vote:
null` again, flipping `VotePanel` back to "unvoted" until the cache
expires.

## Why the feature-flags cache key carries an explicit version segment

The feature-flags cache key is `"api_v1_bootstrap:feature_flags:#{Rails.env}:v1"`.
The environment and the `:v1` version segment are there so that the moment
flags become per-locale or per-user, the key shape is already explicit —
no migration needed to add a locale or user segment later.

## Why the locale list has its own longer TTL

`sway_locales_json` is cached for 300 seconds under
`"api_v1_bootstrap:sway_locales:v1"`. The longer TTL reflects that the
locale list rarely changes, and it absorbs the same launch stampede the
Bill of the Week cache does. The `:v1` suffix again lets the cache be
invalidated by bumping the key if the JSON shape changes. `to_sway_json`
exposes only public fields, no admin metadata.

## Why `show` is a single request

`GET /api/v1/bootstrap` is the single source of truth for mobile app
launch: one request returns everything the app needs to draw its first
screen (current user, locale, Bill of the Week, feature flags, unread
notification count, supported version bounds), rather than the app firing
several separate launch requests.
