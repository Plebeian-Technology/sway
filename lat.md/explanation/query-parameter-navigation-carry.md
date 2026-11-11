---
lat:
  mode: explanation
---
# Query parameter navigation carry

The query parameter carry architecture preserves operator filter and navigation state across transitions through centralized interception and an explicit cleared-value protocol.

## Centralized interception mechanism

Query parameter carry is executed centrally via an Inertia router navigation hook paired with a Rails controller redirect rewrite, providing complete coverage across application visits.

Centralized interception is chosen over per-call-site helpers because per-call-site helpers suffer from omission drift. When state preservation relies on individual components or navigation triggers invoking wrapper functions, newly developed screens, links, and forms frequently omit the helper, causing silent loss of operator state. Centralized interception provides uniform, guaranteed coverage across all navigation surfaces without duplicating boilerplate logic at each call site.

The client-side mechanism registers a `router.on("before")` event hook at module load in `app/frontend/sway_utils/queryParamNavigationCarry.ts` (imported before reload coalescing and layout stores in `app/frontend/entrypoints/application.tsx` so downstream `before` listeners observe the post-carry URL). This hook intercepts outgoing Inertia visits, merges active query parameters from the current URL that belong to the relevant feature boundary or global namespace, and updates the target visit URL before network dispatch. When a prefetch visit (`visit.prefetch === true`) resolves after carry to the exact URL already displayed (`origin`, `pathname`, and `search`), the hook cancels the prefetch with `event.preventDefault()` — `@inertiajs/core` checks `visitUrl === currentUrl` before firing `inertia:before`, so a hover prefetch on `<Link href="/past_bills_of_the_month" prefetch="hover">` while viewing `/past_bills_of_the_month?sway_locale_id=3` would otherwise bypass Inertia's self-prefetch guard and, upon response, trigger `Response#handlePrefetch` to overwrite the active page's resolved deferred props back to `undefined`.

For client GET visits, feature parameters and aliases carry only when source and destination paths resolve to the same feature; global ambient parameters, including `run_id`, cross feature boundaries. Client non-GET visits may carry source- and destination-feature parameters so form state can survive a redirect. The stricter same-bill, digits-only `run_id` rule applies to server redirects below.

Within a feature boundary, parameter carry evaluates semantic families rather than literal keys. Each feature defines an alias map linking canonical parameters to legacy aliases. When the destination URL or visit payload explicitly supplies any parameter belonging to a family, the interceptor suppresses carrying other members of that family, preserving explicit destination choices over implicitly carried state.

To guarantee the interceptor accurately detects query parameters, GET visits must pass query parameters explicitly in the destination URL string (e.g., ``router.get(`${window.location.pathname}?${params.toString()}`, {})``) rather than the Inertia `data` payload. Placing parameters in the `data` payload truncates array values via `Object.fromEntries()` and causes the interceptor to skip applying active URL parameters, which breaks the carry mechanism.

The server-side mechanism pairs the client interceptor with a Rails `after_action` filter for same-origin redirects. It carries only request-URL query pairs that belong to the route boundary and are absent from the redirect destination; form bodies and Referer query strings are not copied.

### Server redirect carry follows real form writes

Rails redirects retain URL state under the same feature and origin rules used by client navigation.

For GET and HEAD requests, the requested path identifies the source feature; Rails routes HEAD through GET. For other methods, only a same-origin Referer path may identify it. The copied values always come from the request URL. Feature-owned values move only when the source and target paths resolve unambiguously to the same feature, while global ambient values can cross feature boundaries. Unknown or ambiguous source paths carry ambient values only.

The filter accepts Rails redirect statuses and same-origin `Location` URLs with the exact scheme, host, and port. It leaves excluded source or destination paths, external redirects, and Inertia conflict responses alone. Existing destination query pairs and fragments are preserved. A target key in a semantic family suppresses the incoming family, including an explicit empty value; when an ordinary registered key starts with an empty value, every repeated value for that key is removed. The Bill Creator run pin carries only as one digits-only value between routes for the same bill. The empty `selected_stages` and `stages` list remains a meaningful selection.

The form boundary is covered by [[spec/requests/organization_follows_spec.rb]]: a follow write carries `org_tab=members` through a same-feature redirect, and following the location renders the membership page with its `tab` prop set to `members`. A client-cleared value stays absent from the POST URL and from the current Referer after the client has cleared it.

High-security and machine-oriented namespaces are deliberately excluded from parameter carry. The mobile JSON API (`/api/v1/`), internal web API (`/api/`), and authentication and registration routes (`/sessions`, `/passkeys`, `/registrations`, `/phone_verification`, `/sway_registration`) bypass parameter carry entirely. This boundary prevents ambient operator parameters from leaking into credential exchanges, session establishment, or automated machine endpoints.

## Excluded route constants and security boundaries

High-security and machine-oriented namespaces are deliberately excluded from parameter carry through checked constants in both frontend and backend runtimes.

The exclusion boundary prevents ambient operator query parameters from leaking into credential exchanges, WebAuthn sessions, passkey registrations, phone verification, or automated machine API endpoints. Rather than relying on unvalidated path assertions at individual call sites, the exclusion list is formalized as checked constants: `NAVIGATION_EXCLUDED_ROUTE_PREFIXES` (with `isNavigationExcludedRoute`) in `app/frontend/sway_constants/navigation.ts` and `NavigationRouteExclusions::EXCLUDED_PREFIXES` in `lib/navigation_route_exclusions.rb`.

Both constants cover `/api/v1`, `/api`, `/sessions`, `/test/sessions`, `/passkeys`, `/registrations`, `/phone_verification`, `/sway_registration`, `/users/webauthn`, and `/users/passkeys`. Request specs and Vitest suites verify these prefixes directly against `config/routes.rb` and standard navigation routes to catch accidental omissions whenever new endpoints are introduced.

## The cleared-on-purpose signal

Deliberate parameter removal is signaled across transport boundaries by specifying an empty parameter value in the destination query string.

When navigation state is carried automatically, an interceptor must distinguish between an omitted parameter ("this parameter was not mentioned, so the active value must be retained") and an intentional removal ("this filter was deliberately cleared, so the previous value must not carry forward").

The URL query string is the sole universal transport medium shared across Inertia client visits, standard HTML `<a>` links, JavaScript fetch requests, and HTTP 302 redirect `Location` headers. Alternative mechanisms—such as in-memory event buses, sessionStorage flags, or custom HTTP headers—fail across full-page reloads, server-side redirects, or plain HTML anchor tags. Furthermore, dedicated sentinel strings (such as `__cleared__` or `null`) pollute the address bar, risk leaking into database queries, and require custom parsing across diverse endpoints. An empty string value (`?param=` or `params.set("param", "")`) represents standard URL syntax and functions universally.

The centralized interceptor inspects the target query string before dispatch. When the interceptor detects a parameter present with an empty value (`""`), it distinguishes between generic parameter clearance and intentional empty lists. For ordinary parameters (`run_id`, `search`, `page`, etc.), it recognizes an intentional clearance instruction, suppresses parameter carry from the current URL, and strips the key entirely before network dispatch so the server observes omission. For registered intentional empty list parameters (`selected_stages`, `stages`), an empty value represents an explicit zero-item selection rather than clearance, and is preserved in the dispatched query string. Because the empty string represents zero stages for `selected_stages` and `stages`, returning to the default stage set omits the family from both the destination URL and `visit.data` on a partial reload that requests `selected_stages` in `visit.only`, and the interceptor skips carrying that family from the current URL.

The implementation in `app/frontend/sway_utils/queryParamClearedSignal.ts` provides `setQueryParamCleared`, `isQueryParamCleared`, and `stripClearedQueryParams`. Callers mark a parameter cleared on `URLSearchParams`, `URL`, or path strings, setting its value to `""` while cleaning up any duplicate bracketed spellings. When an Inertia navigation begins, `registerClearedParamStripPoint` intercepts the `router.on("before")` event and executes `stripClearedQueryParamsFromVisit`, removing generic cleared keys from the visit destination URL while preserving intentional empty lists before the network request leaves.

Every ordinary deliberate removal site across the frontend—including `currentAddressWithout`, default sort selection in `useUrlSort`, empty search terms in `useDebouncedUrlSearch`, pagination resets on locale changes in `useLocales`, default tab selection in `Legislators.tsx`, and returning to the auto-latest run in `RunSelector.tsx`—invokes `setQueryParamCleared` so that the intended clearance survives centralized query parameter carry.

## Harmonization of architectural documentation

The adoption of an explicit clearance protocol harmonizes the standing documentation by resolving the historical objection to router interception.

Historically, `docs/explanation/current-address-without-owned-params.md` argued against registering a router interceptor, observing that an unguarded interceptor could not distinguish parameter omission from deliberate clearance and would resurrect intentionally dropped filters such as `run_id`, `page`, and reset list parameters. Simultaneously, the maintainer's working notes preferred centralized interception over repeated call-site handling, noting that absence and intentional removal required distinct handling.

This contradiction is resolved by coupling centralized interception with the empty-value clear protocol. The historical objection correctly identified the flaw in an unguarded interceptor that equates absence with persistence. When callers explicitly signal removal through an empty parameter value (`?param=`), the interceptor possesses the necessary context to distinguish deliberate clearance from omission. Centralized interception with explicit clearance therefore represents the authoritative architectural decision, reconciling both documents.

## Retirement of hand-rolled call-site carry

The introduction of centralized parameter carry retires legacy call-site helpers that manually duplicated query parameters into visit data or destination URLs.

Prior to centralized interception, the admin Bill Creator manually preserved query parameters via two separate helpers: `collectQueryParams` (which copied active search params into `visit.data`) and `withCarriedRunPin` (which appended `run_id` onto destination tab paths). This caused `run_id` to be carried redundantly in both path query strings and visit payloads, while arbitrary un-namespaced query parameters leaked across tabs.

With the centralized `router.on("before")` interceptor and `config/query_parameters.yml` active, `collectQueryParams` and `withCarriedRunPin` were retired under centralized navigation carry (decided in [[query-parameter-navigation-carry#Query parameter navigation carry]]). The Bill Creator dispatches visits with its canonical `bill_creator_tab` component data, and the interceptor carries registered operator controls—including `selected_stages`, `download_missing_assets`, `subject`, `severity`, `window`, `cursor`, `date`, and `highlight` alongside ambient `run_id` and `sway_locale_id`—to destination URLs according to declared feature ownership.

## Dependent migration issues

This architectural decision establishes the foundation for enabling application-wide parameter carry across six sequential backlog issues.

The downstream dependencies unblocked by this decision are:

- Cleared parameter signal: Implements the universal empty-value clearance helper and the interceptor strip point.
- Deliberate parameter removals: Converts all ordinary parameter removals across hooks, pages, and utilities to emit the cleared signal.
- Checked route exclusion constant: Formalizes the excluded route namespaces into a validated constant.
- Application-wide carry registration: Registers the centralized `router.on("before")` interceptor in the frontend application entrypoint.
- Redirect location rewriting: Implements the Rails controller `after_action` filter that preserves query parameters across HTTP redirects.
- Retirement of hand-rolled carry: Retires `collectQueryParams` and `withCarriedRunPin` from the Bill Creator in favor of centralized carry.
