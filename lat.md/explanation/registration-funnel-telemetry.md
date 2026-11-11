---
lat:
  mode: explanation
---
# Registration funnel telemetry

Sway measures voter onboarding conversion through self-hosted telemetry without external analytics trackers. The registration lifecycle spans public landing, phone verification, passkey enrollment, geocoding, and first vote.

## Event schema and database storage

Funnel events are stored in the append-only `registration_funnel_events` table optimized for SQLite WAL mode. Rows omit `updated_at` to prevent write amplification on the single-node host.

The schema records a `visitor_token` UUID identifying unique browser sessions prior to authentication, an optional `user_id` foreign key linked upon enrollment, an integer `step` enum, a referral `attribution_key`, and a bounded JSON `metadata` payload. Composite indexes on `[step, created_at]`, `[bot, created_at, step]`, `visitor_token`, and `[attribution_key, created_at]` support sub-millisecond filtering across date ranges. When users delete their accounts, foreign keys nullify rather than deleting historical metrics.

## Client-side telemetry dispatch and step mapping

Client telemetry dispatches non-blocking events using `navigator.sendBeacon` with a `fetch` keepalive fallback. Payloads omit all personally identifiable information such as phone numbers or addresses.

The client tracker maps the primary onboarding progression: `landing` on public pages, `phone_entered` in the passkey panel, `sms_verified` after carrier confirmation, `passkey_enrolled` following biometric creation, `address_submitted` upon jurisdiction entry, `registration_completed` when district assignment finishes, and `first_vote_cast` when a ballot is submitted. Sub-events capture ceremony cancellations and validation errors to surface granular drop-off friction without transmitting sensitive input values.

## Ingestion API and rate limiting

The public ingestion endpoint at `POST /api/v1/funnel_events` validates step enumerations and clamps metadata payloads. Rails 8 rate limiting restricts incoming telemetry to sixty requests per minute per IP.

Operating behind `Api::V1::BaseController` with `public_endpoint?` enabled, the controller associates incoming events with the authenticated bearer user or, for browser onboarding telemetry when no token is supplied, with the ambient session user. If an API token is supplied, it is authoritative and invalid credentials record anonymous events without cookie fallback. Metadata dictionaries are pruned to primitive scalar values and capped in size to prevent storage exhaustion. Malformed step names receive an unprocessable entity status code rather than crashing ingestion workers.

## Attribution preservation

Attribution keys from referral links such as `/s/:key` or invite parameters are stored in first-party cookies. Cookies survive session fixation resets during user authentication to maintain conversion tracking.

When visitors follow a shortened URL or an invite link, the attribution key is stored in permanent first-party cookies. When the user verifies their phone and creates an account, `ApplicationController#sign_in` transfers both the attribution key and anonymous visitor token across the session reset boundary. This guarantees that initial marketing campaigns receive credit when the newly enrolled constituent eventually casts their first vote.

## Registration funnel metrics and friction ranking

`RegistrationFunnelMetricsService` aggregates step counts and calculates step-to-step drop-offs in a single pass. Transitions between consecutive steps are ranked by absolute loss and percentage drop-off rate.

Step counts represent distinct visitors reaching each milestone within the selected time window. The service evaluates transitions between adjacent steps as friction points, ordering them both by absolute volume loss and percentage leak. Referral sources are broken down by visitor counts, completed registrations, and voting conversion rates. Async geocoding latencies compute median and ninety-fifth percentile durations from monotonic timing measurements.

## Registration funnel serialization

`RegistrationFunnelResource` inherits `ApplicationResource` and exposes exact-keyed attributes for admin consumption. Serialized properties include step metrics, friction rankings, and latency percentiles.

The resource follows Alba serialization patterns and guarantees a predictable property contract. The serialized payload includes `traffic`, `traffic_options`, and `bot_visitor_count` so the client dashboard can render active filtering states without client-side guessing. Tests in `spec/requests/serializer_whitelists_spec.rb` assert the exact key set to prevent accidental schema leakage or regressions during refactoring.

## Admin registration funnel dashboard

The admin dashboard at `/admin/registration_funnel` renders interactive conversion reports with live polling. Controls satisfy forty-four pixel touch target guidelines without horizontal overflow on mobile.

The dashboard presents summary cards for landing visitors, registrations, and votes, followed by visual progression bars for each funnel stage. Operators can toggle friction ranking by user count or drop-off rate, inspect asynchronous geocoding latency percentiles, and filter traffic by referral source. Touch targets meet accessibility minimums, and background polling keeps statistics fresh without full page reloads.

## Bot traffic classification

Sway classifies incoming registration funnel telemetry as human or bot traffic at ingestion time, preventing automated web crawlers and API callers from distorting public onboarding conversion metrics.

Public ingestion at `POST /api/v1/funnel_events` accepts anonymous browser traffic, leaving the `landing` stage susceptible to search engine spiders, automated vulnerability scanners, and scripted HTTP clients. [[app/lib/bot_user_agent.rb#BotUserAgent]] evaluates the request `User-Agent` against known crawler patterns, headless browser identifiers, and automated HTTP libraries. Missing or blank user agents default to bot classification because standard browser beacon dispatches supply standard browser identities. In addition, telemetry emitted by registered API testing accounts (`User#is_sway_api_user?`) is flagged as bot traffic to keep automated API verification separate from real civic constituent activity.

Historical funnel events predating the `bot` column default to `bot = false` without speculative backfills, avoiding heuristic misclassification of past real voters.

### User agent matching and byte sequence scrubbing

User agent classification evaluates incoming header strings against crawler patterns while defending against malformed byte sequences.

Automated HTTP clients, headless automation drivers (such as Puppeteer, Playwright, and Selenium), and search crawlers are identified via [[app/lib/bot_user_agent.rb#BotUserAgent]]. To avoid false positives on consumer device brands, the pattern employs negative lookbehinds on hardware tokens like Cubot. Request headers containing non-UTF-8 or malformed byte sequences are scrubbed via `String#scrub` before evaluation, ensuring that malformed spider requests return valid telemetry status codes rather than raising unhandled encoding exceptions.

### Verified users reclassify their visitor token

When an anonymous session subsequently completes phone verification or passkey enrollment, earlier events associated with that session's `visitor_token` are retroactively marked as human.

Initial landing beacons often arrive before client capabilities or user intent can be proven. Once a visitor successfully links an account or advances through SMS verification and geocoding via [[app/models/registration_funnel_event.rb#RegistrationFunnelEvent#mark_visitor_human!]], Sway updates earlier bot-classified events sharing that `visitor_token` to `bot: false`. This ensures real voters who arrived on privacy browsers or under atypical user agents are not excluded from landing and mid-funnel conversion totals.

### Traffic filter on the admin dashboard

The registration funnel dashboard allows administrators to toggle between human traffic, bot traffic, or aggregate volume.

The `traffic` query parameter defaults to `humans`, filtering queries to `bot: false` so that drop-off rankings reflect genuine constituent friction. Toggling to `bots` isolates automated crawler volume and bot landing spikes, while `all` displays total ingestion volume. The interface exposes the count of filtered bot visitors within the active time window, giving operators immediate visibility into background scanning noise.
