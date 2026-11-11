---
mode: explanation
summary: "Why FaradayStack extends the default retry exceptions for read-only upstreams, and why there is deliberately no shared llama.cpp connection method."
status: agent-extracted
related: []
---

<!-- vale Vale.Spelling = NO -->

# FaradayStack: retry exceptions and the missing llama.cpp connection

`Sway::FaradayStack` is the shared factory every outbound HTTP call in the
legislation pipeline builds its `Faraday::Connection` through, so retry
behavior, timeouts, and middleware stay uniform. Two decisions in this file
are not obvious from the code alone.

## Why TRANSPORT_RETRY_EXCEPTIONS extends the gem default

`faraday-retry`'s `DEFAULT_EXCEPTIONS` covers timeouts
(`Errno::ETIMEDOUT`, `Timeout::Error`, `Faraday::TimeoutError`) and the
synthetic `Faraday::RetriableResponse` — but not dropped connections. Public
APIs like Legistar sometimes close the TLS socket mid-response, which
Faraday reports as `Faraday::SSLError` ("SSL_read: unexpected eof while
reading") or `Faraday::ConnectionFailed`. Because those classes were missing
from the retry list, one mid-read EOF on a single bill's
`/Matters/:id/Attachments` fetch aborted an entire discovery run without any
of the configured `max:` retries ever being attempted.

`TRANSPORT_RETRY_EXCEPTIONS` extends (does not replace) the gem default: the
timeout coverage stays, and connection-drop coverage is added. It's applied
to the read-only external profiles — `LEGISTAR_DEFAULTS`, `GITHUB_DEFAULTS`,
`OPEN_DATA_DEFAULTS`.

`LEGISTAR_DEFAULTS` lists `post` in `methods:` even though re-sending a
half-sent POST is normally unsafe, because Legistar's OData query endpoints
are read-only no matter the verb, so retrying them cannot write twice.

`LLAMACPP_DEFAULTS` deliberately leaves these transport exceptions out: a
mid-read drop on a completion POST must not silently re-run inference, so it
keeps the gem's timeout-only default.

## Why there is no `.llamacpp` connection method

Every other upstream (`legistar`, `github`, `open_baltimore`, `wikidata`,
`open_states`, `congress_gov`, `congress_legislators`) gets a
`Sway::FaradayStack.xxx` builder method. A `.llamacpp` one is deliberately
absent — only the `LLAMACPP_DEFAULTS` retry options above exist.

There used to be one, and nothing ever called it. `Llm::LlamacppAdapter`
builds its own `OpenAI::Client` — the `ruby-openai` gem wants a base URL and
a timeout of its own — and borrows only the retry options from this module.
This module ended up holding a second llama.cpp connection, with a second
120-second deadline, that no request ever traveled through.

That invites a wrong fix. Asked to make the llama.cpp deadline
settable, the fix changed the 120 here, proved it with specs, and shipped
it — and it altered nothing. The live deadline is
`Llm::LlamacppAdapter::DEFAULT_REQUEST_TIMEOUT_SECONDS`. Two constants held
the same value on the same conceptual path, and only one of them was real.

Adding a connection back here would rebuild that trap. If llama.cpp ever
needs one, delete the adapter's own client in the same change.

## Migration history: replacing raw Faraday calls

`.open_states` and `.congress_gov` both replace an earlier bare Faraday call
that raised on the first blip:

- `.open_states` (the OpenStates v3 API) replaced a bare `Faraday.get`.
- `.congress_gov` (the congress.gov v3 API, used by the weekly
  `CongressRefresh` legislators-cache roster fetch) replaced a bare
  `Faraday.new`. `OPEN_DATA_DEFAULTS`'s bounded 429/5xx retries mean one blip
  mid-pagination no longer aborts the whole run.

## Why `.congress_legislators` has a longer timeout

`.congress_legislators` fetches the `unitedstates/congress-legislators` data
files. Its timeout (120s) is longer than every other profile because one of
the two files it fetches is 13 MB.

## Why OpenStates and congress.gov auth stays a query param

`.open_states` (used by registration geo lookup and the Maryland
legislators-cache refresh) authenticates with the `apikey` query param,
matching the OpenStates convention and `maryland_refresh.rb`; callers pass it
as a request param.

`.congress_gov` keeps its API key as a query param too (congress.gov
convention); callers pass it as a request param.

## Why `.open_baltimore`'s base URL must keep its trailing slash

`.open_baltimore` builds the connection for the Open Baltimore ArcGIS
Feature Service — the live Baltimore City Council District roster. The
base URL carries the ArcGIS org id and services root, and MUST keep its
trailing slash so `OpenBaltimore::Client`'s relative resource paths
resolve under it, the same shape of requirement as `.congress_legislators`
below.

## Why `.congress_legislators`'s base URL must keep its trailing slash

`.congress_legislators` fetches the `unitedstates/congress-legislators` data
files, which say how long each member of Congress really held each seat
(`LegislatorsCache::CongressTermHistory`). No key, no query params — two
plain files. The base URL MUST keep its trailing slash so the file names
resolve under it.

## Why the `.legistar` env-override specs use `with_app_config`, not `with_env`

`Sway::Settings.upstream` is memoized, built once at boot, so a value
handed to `with_env` after boot never reaches it — only a fresh settings
instance re-reads `ENV`. `spec/lib/sway/faraday_stack_spec.rb`'s
`.legistar` examples use `with_app_config`, which swaps in a fresh instance
built from the given override, exercising the same caster and blank-repair
pipeline a real environment variable goes through
(`Sway::Settings::Base#write_config_attr` treats every source uniformly).

One example still has to prove a real environment variable reaches this
call site end to end, so it builds `Sway::Settings::Upstream.new` directly,
under a real `with_env`, bypassing the memoized reader on purpose.
