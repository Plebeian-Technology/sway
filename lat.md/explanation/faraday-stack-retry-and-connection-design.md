---
lat:
  mode: explanation
---

# FaradayStack: retry exceptions and the missing llama.cpp connection

`Sway::FaradayStack` is the shared factory every outbound HTTP call in the legislation pipeline builds its `Faraday::Connection` through, so retry behavior, timeouts, and middleware stay uniform.

Two decisions in this file are not obvious from the code alone.

## Why TRANSPORT_RETRY_EXCEPTIONS extends the gem default

`faraday-retry`'s `DEFAULT_EXCEPTIONS` covers timeouts (`Errno::ETIMEDOUT`, `Timeout::Error`, `Faraday::TimeoutError`) and the synthetic `Faraday::RetriableResponse` — but not dropped connections.

Public APIs like Legistar sometimes close the TLS socket mid-response, which Faraday reports as `Faraday::SSLError` ("SSL_read: unexpected eof while reading") or `Faraday::ConnectionFailed`. Because those classes were missing from the retry list, one mid-read EOF on a single bill's `/Matters/:id/Attachments` fetch aborted an entire discovery run without any of the configured `max:` retries ever being attempted.

`TRANSPORT_RETRY_EXCEPTIONS` extends (does not replace) the gem default: the timeout coverage stays, and connection-drop coverage is added. It's applied to the read-only external profiles — `LEGISTAR_DEFAULTS`, `GITHUB_DEFAULTS`, `OPEN_DATA_DEFAULTS`.

`LEGISTAR_DEFAULTS` lists `post` in `methods:` even though re-sending a half-sent POST is normally unsafe, because Legistar's OData query endpoints are read-only no matter the verb, so retrying them cannot write twice.

`LLAMACPP_DEFAULTS` deliberately leaves these transport exceptions out: a mid-read drop on a completion POST must not silently re-run inference, so it keeps the gem's timeout-only default.

## Why there is no .llamacpp connection method

Every other upstream (`legistar`, `github`, `open_states`, `congress_gov`, `congress_legislators`) gets a `Sway::FaradayStack.xxx` builder method.

A `.llamacpp` one is deliberately absent — only the `LLAMACPP_DEFAULTS` retry options above exist.

There used to be one, and nothing ever called it. `Llm::LlamacppAdapter` builds its own `OpenAI::Client` — the `ruby-openai` gem wants a base URL and a timeout of its own — and borrows only the retry options from this module. This module ended up holding a second llama.cpp connection, with a second 120-second deadline, that no request ever traveled through.

That invites a wrong fix: a change to make the llama.cpp deadline settable could edit the 120 here, pass its specs, and alter nothing. The live deadline is `Llm::LlamacppAdapter::DEFAULT_REQUEST_TIMEOUT_SECONDS`. Two constants held the same value on the same conceptual path, and only one of them was real.

Adding a connection back here would rebuild that trap. If llama.cpp ever needs one, delete the adapter's own client in the same change.

## Migration history: replacing raw Faraday calls

`.open_states` and `.congress_gov` both replace an earlier bare Faraday call that raised on the first blip:

- `.open_states` (the OpenStates v3 API) replaced a bare `Faraday.get`.
- `.congress_gov` (the congress.gov v3 API, used by `FetchBillsService`,
  `FetchHearingsService` and the House legislator-vote scraper) replaced a bare
  `Faraday.new`. `OPEN_DATA_DEFAULTS`'s bounded 429/5xx retries mean one blip
  mid-pagination no longer aborts the whole run. The weekly legislators-cache
  roster fetch (`LegislatorsCache::BaseRefresh`) does not use this profile:
  `Legislation::Adapters::GenericRosterAdapter` opens a plain Faraday
  connection with no retries.

## Why .congress_legislators has a longer timeout

`.congress_legislators` fetches the `unitedstates/congress-legislators` data files. Its timeout (120s) is longer than every other profile because one of the two files it fetches is 13 MB.

## Why OpenStates and congress.gov auth stays a query param

[[lib/sway/faraday_stack.rb#FaradayStack#open_states]] (used by registration geo lookup and the Maryland legislators-cache refresh) authenticates with the `apikey` query param, matching the OpenStates convention and [[app/services/legislation/adapters/generic_roster_adapter.rb]]; callers pass it as a request param.

[[lib/sway/faraday_stack.rb#FaradayStack#congress_gov]] keeps its API key as a query param too (congress.gov convention); callers pass it as a request param.

## Why CongressGovErrorReporter mounts outer to retry middleware

[[lib/sway/faraday_stack.rb#FaradayStack#congress_gov]] mounts [[lib/sway/faraday_stack.rb#CongressGovErrorReporter]] outer to retry middleware so Sentry notifications dispatch only once after transient retries are exhausted while scrubbing sensitive credentials.

[[lib/sway/faraday_stack.rb#FaradayStack#congress_gov]] builds the Faraday connection for the official Congress.gov v3 REST API. During connection initialization, the stack inserts [[lib/sway/faraday_stack.rb#CongressGovErrorReporter]] at index 0 of the handler chain (`conn.builder.insert(0, Sway::FaradayStack::CongressGovErrorReporter)`).

Faraday processes response middleware in reverse registration order. Because index 0 sits at the outermost boundary of the handler stack, outer to `Faraday::Retry::Middleware`, [[lib/sway/faraday_stack.rb#CongressGovErrorReporter#on_complete]] executes only after the inner retry middleware has either succeeded or exhausted all configured attempts under [[lib/sway/faraday_stack.rb#FaradayStack#OPEN_DATA_DEFAULTS]]. Transient 429 rate limits or ephemeral 5xx gateway blips that resolve upon retry complete without emitting alerts, preventing Sentry alert noise during routine network jitter.

When a final response terminates with an HTTP status code of 400 or greater, [[lib/sway/faraday_stack.rb#CongressGovErrorReporter]] intercepts the completed environment. Before dispatching request and response metadata to Sentry via `Sentry.capture_message`, the reporter scrubs any `api_key` query parameter matching `(\bapi_key=)[^&#\s]*` to `[FILTERED]`. This ensures API tokens are never exposed in Sentry exception payloads, stack traces, or diagnostic breadcrumbs.

To prevent Sentry issue saturation, the reporter normalizes error telemetry across two dimensions. First, it uses the constant error message `"Congress.gov API HTTP error"` and constructs a fingerprint array `["congress_gov_http", status, path_template]` where `path_template` replaces all digit-only path segments with `:n` using `env.url.path.to_s.gsub(%r{(?<=/)[0-9]+(?=/|$)}, ':n')`. This groups errors by endpoint pattern rather than creating isolated Sentry issues for every bill, roll-call, or hearing ID. Second, it suppresses Sentry dispatch entirely when the status is 404 and the path template ends with `/house-vote/:n/:n/:n/members`. Because Congress.gov publishes House roll calls roughly a day after floor votes, 404 responses on recent roll calls are expected and handled downstream by the House scraper's Clerk XML fallback. Suppressing these expected 404s prevents telemetry storms during normal vote ingestion.

## Roll-call fetch retry disposition and Sentry alerts

[[app/jobs/legislator_vote_fetch_job.rb#LegislatorVoteFetchJob]] paces retries for unavailable roll calls while bubbling permanent verification errors immediately to Sentry.

When [[lib/sway/faraday_stack.rb#FaradayStack#congress_gov]] and its fallback stages encounter unavailable upstream data, error handling and alerting transition to [[app/jobs/legislator_vote_fetch_job.rb#LegislatorVoteFetchJob]] and [[app/services/congress_legislator_vote_update_service.rb#CongressLegislatorVoteUpdateService]]:

1. **Production routing**: On the production path, [[app/jobs/legislator_vote_fetch_job.rb#LegislatorVoteFetchJob#run_service_for]] inspects jurisdiction rules and routes federal legislation directly to [[app/services/congress_legislator_vote_update_service.rb#CongressLegislatorVoteUpdateService]] rather than generic adapters.
2. **Retry disposition for unavailable votes**: If either chamber cannot fetch a roll call because Congress.gov and secondary fallback stages fail, the scraper raises [[app/scraper/scraper/congress/roll_call_unavailable.rb#RollCallUnavailable]]. [[app/jobs/legislator_vote_fetch_job.rb#LegislatorVoteFetchJob]] declares `retry_on Scraper::Congress::RollCallUnavailable, wait: 1.hour, attempts: 3`. This accommodates upstream publication delays without worker congestion.
3. **Selective suppression of intermediate Sentry alerts**: [[lib/sway/faraday_stack.rb#CongressGovErrorReporter]] suppresses only HTTP 404 responses on `/house-vote/{congress}/{session}/{roll}/members`; non-404 Congress.gov HTTP errors (such as 403 or retry-exhausted 5xx responses) are still reported immediately via [[lib/sway/faraday_stack.rb#CongressGovErrorReporter]]. In contrast, Senate primary and Voteview fallback failures, as well as House 404 responses paired with Clerk XML fallback failures, do not capture inline Sentry exceptions and instead alert Sentry only if all three [[app/jobs/legislator_vote_fetch_job.rb#LegislatorVoteFetchJob]] attempts fail.
4. **Immediate failure on identity mismatches**: In contrast to transient availability errors, permanent identity verification failures—specifically [[app/scraper/scraper/congress/roll_call_mismatch.rb#RollCallMismatch]] (mismatched vote dates) and [[app/scraper/scraper/congress/roll_call_not_on_the_bill.rb#RollCallNotOnTheBill]] (procedural or cloture motions)—are neither retried (`retry_on`) nor discarded (`discard_on`). These exceptions propagate immediately out of the job, generating an actionable Sentry alert without wasteful retries.

## Why .congress_legislators's base URL must keep its trailing slash

`.congress_legislators` fetches the `unitedstates/congress-legislators` data files, which say how long each member of Congress really held each seat (`LegislatorsCache::CongressTermHistory`).

No key, no query params — two plain files. The base URL MUST keep its trailing slash so the file names resolve under it.

## Why the .legistar env-override specs use with_app_config, not with_env

[[lib/sway/settings.rb#Settings|Sway::Settings.upstream]] is memoized and built once at boot, so a value handed to `with_env` after boot never reaches it — only a fresh settings instance re-reads `ENV`.

`spec/lib/sway/faraday_stack_spec.rb`'s `.legistar` examples use `with_app_config`, which swaps in a fresh instance built from the given override, exercising the same caster and blank-repair pipeline a real environment variable goes through (`Sway::Settings::Base#write_config_attr` treats every source uniformly).

One example still has to prove a real environment variable reaches this call site end to end, so it builds `Sway::Settings::Upstream.new` directly, under a real `with_env`, bypassing the memoized reader on purpose.

## OpenRouter retries and upstream User-Agent headers

[[lib/sway/faraday_stack.rb]] restricts `OPENROUTER_DEFAULTS` retries to HTTP `429` and transport exceptions, and attaches explicit `User-Agent` headers on the GitHub and Nominatim connection profiles.

Retrying `5xx` responses against OpenRouter could trigger duplicate paid model executions when an upstream request already started, whereas `api.github.com` and Nominatim reject or throttle requests that omit an identifying `User-Agent`.

## Why the Nominatim connection never retries

[[lib/sway/faraday_stack.rb#FaradayStack#nominatim]] makes one attempt and waits at most 3 seconds for it: `NOMINATIM_DEFAULTS` retries no status, no timeout and no transport failure.

The public Nominatim server allows about one request per second, and [[app/services/nominatim_service.rb#NominatimService#REQUESTS_PER_SECOND|the service's cap]] counts each search once, before it is sent. A retry inside the connection is a second request the cap never sees, so three retries on a server error could send four requests in the second the cap allowed one. A `429` means Sway is already over that limit, and a retry adds load at the moment the server asks Sway to slow down.

Nominatim also serves address autocomplete while a user types, and [[address-place-classification#Nominatim place classification and usage constraints|the search falls back to Google Places]] when Nominatim gives no answer. With a 10-second timeout and three retries on transport failures, a hung Nominatim held each suggestion request for about 40 seconds, so the fallback never answered in time. A single 3-second attempt keeps the worst case short, and a failed attempt goes to the fallback rather than to Nominatim again. The next keystroke is the retry.
