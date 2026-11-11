---
lat:
  mode: explanation
---
# System shape

Sway is one Rails process serving one React bundle, with Inertia between them instead of a JSON API. The shape follows from a single constraint: one operator, one small machine, three jurisdictions, and no appetite for a second deployable.

Every other structural decision on this page is downstream of that constraint —
the datastore, the job runner, the way scores reach a browser, and the way the
mobile app is fed.

## One process, two languages

Rails 8.1 on Ruby 4.0.7 and React 19 on TypeScript 6 are not two applications
here. A controller answers with `render inertia: "PageName", props: {...}`, and
the named component under `app/frontend/pages/` receives those props directly.

The consequence worth internalising is that a page's data contract lives in the
controller, not in a fetch call. There is no endpoint to version, so
data-shaping belongs in `app/serializers/` alba resources, letting the prop and
the mobile JSON body come from the same place.

Inertia prefetch and encrypted history can reuse a page without a fresh server
render, so they must be cleared when the signed-in user changes. The service
worker caches static assets only; dynamic pages require the network. That
boundary is the subject of [[client-caches-and-identity]].

The UI is Radix primitives over Tailwind, with a vendored shadcn island in
`app/frontend/components/ui/` that keeps its own conventions.

### A component file exports components and nothing else

Helpers used by a component live in their own file rather than beside it.

Exporting a plain function from a component file breaks fast refresh: the
tooling can no longer tell that the module is a component module, so an edit
reloads the page instead of swapping the component, and the state the developer
was looking at is gone. The lint rule that reports it is describing a real
consequence rather than a preference.

### Why a payload goes through a resource rather than the record

Handing an ActiveRecord object to `render json:` publishes whatever columns the
table happens to have, which is wrong in both directions.

It sends too much: every column travels, so a column added for internal
bookkeeping becomes part of a public response the day it is created, and an
endpoint serving signed-out readers turns into an information-disclosure hole
without anyone editing it. It also sends too little, because the computed
values a payload is expected to carry — a district's number and region code,
an organization's follower count — are not columns and never appear.

A resource states the key set instead, so both faults are visible in one file
and an exact key-set request spec can pin it.

Sway's [[app/serializers/application_resource.rb#ApplicationResource|Alba resources]]
can serialize a collection through one resource instance. A record-dependent
instance-variable memo can therefore return the first record's data for later
records. Safe memoization includes record identity and all relevant parameters,
such as locale. Comparing two distinct records serialized together with their
independent results detects this error; reversed order and empty-first cases
also expose accidental reuse.

A resource is asked for its hash while the props are being assembled, not while
the response is being written, which is what lets `render_inertia_or_json` hand
the same hash to an Inertia render and to a mobile JSON body without either
surface knowing which one it is.

The `alba-inertia` companion gem would resolve resources inside the controller
instead, and its controller DSL is deliberately left unwired. Adopting it means
replacing the prop hash that helper is built around, and the gem is still on the
0.1 series, so the trade is a rewrite of the one seam both surfaces share in
exchange for a dependency whose interface can still move. That trade is worth
reopening once the gem is past 0.1.x.

### The bill page composes a page payload from several contracts

The Bill page combines one bill record with reader- and locale-specific values, so its payload needs a composition resource rather than the Bill row alone.

[[app/models/bill.rb#Bill#render]] delegates page props to [[app/serializers/bill_resource.rb#BillResource#page_props]], which builds the eleven-key composition in [[app/serializers/bill_page_resource.rb#BillPageResource]]. The entry point returns a symbol-keyed prop hash for controller callers that add values before rendering. The nested `bill` keeps [[app/serializers/bill_resource.rb#BillResource]] as its contract, while matching nested shapes continue to use [[app/serializers/user_vote_resource.rb#UserVoteResource]], [[app/serializers/news_article_resource.rb#NewsArticleResource]], and [[app/serializers/news_article_testimony_resource.rb#NewsArticleTestimonyResource]].

Where the legacy nested shape differs, the composition uses [[app/serializers/bill_page_legislator_resource.rb#BillPageLegislatorResource]], [[app/serializers/bill_page_district_resource.rb#BillPageDistrictResource]], [[app/serializers/bill_page_organization_bill_position_resource.rb#BillPageOrganizationBillPositionResource]], [[app/serializers/bill_page_organization_resource.rb#BillPageOrganizationResource]], [[app/serializers/legislator_vote_resource.rb#LegislatorVoteResource]], [[app/serializers/roll_call_resource.rb#RollCallResource]], [[app/serializers/bill_score_resource.rb#BillScoreResource]], [[app/serializers/bill_score_district_resource.rb#BillScoreDistrictResource]], and, for mobile JSON only, [[app/serializers/bill_score_district_with_legislator_names_resource.rb#BillScoreDistrictWithLegislatorNamesResource]]. This preserves the page's established response shapes instead of borrowing a similar-looking resource with different keys.

[[app/serializers/bill_page_resource.rb#BillPageResource]] carries callables and `InertiaRails.optional` values to the existing resolver. While Alba builds each prop, it copies the current user and locale from resource params into local variables before constructing inner callables; Inertia later invokes those callables with the controller as their receiver, and the captured locals retain the original request context. The detailed evaluation and JSON omission rules remain in [[lazy-inertia-props#Current optional and deferred JSON props]].

## Why there is no client-side router

Inertia replaces the router rather than sitting beside one. Navigation is a
server round trip returning the next page's props, so authorization, locale
resolution and prop freshness are decided in one place for every surface.

The cost is that anything the client would normally do with local state has to
be expressed as a partial reload: `router.reload({ only: [...] })` fetches a
named subset of props from the same controller action. That is why prop names
appear in frontend code at all, and why the lists of them are pinned in
`docs/reference/partial-reload-prop-lists.md`.

The one exception is state nothing server-side reads at all. The
[[app/frontend/pages/Notifications.tsx#Notifications]] open tab is written
straight into the address with `history.replaceState` rather than a round
trip, because no controller action's props depend on it.

The reasoning behind that one exception is [[notifications-tab-url]].

## What a reader sees during the round trip

A server round trip is visible, so a qualifying visit replaces the page being left with the destination's placeholder. Which visits qualify is decided from what a visit states, never from how long it takes.

`app/frontend/navigation/` holds three pieces: [[app/frontend/navigation/navigationGate.ts#qualifiesForPlaceholder]] decides whether a visit qualifies, `navigationStore.ts` tracks the one in flight, and `placeholderRegistry.ts` maps a pathname to one of eight shapes. `PageBodySlot` sits inside both layouts and stacks the outgoing page and the placeholder in a single grid cell.

Two constraints shaped it. The gate reads `only`/`except`, `prefetch`, `async`, `preserveState` and `method` — all of them things a visit declares — because the fifteen-second score sync and the Bill Creator's five-second poll are visits too, and a timing heuristic would turn them into a strobe. The registry maps addresses rather than importing page components, because pages are code-split: waiting for the destination component in order to draw its skeleton would put the skeleton behind the very download it exists to cover.

The drawer, offline banner and version footer stay outside the treated region, so a reader who is waiting can still go somewhere else.

### Transport failures need a handled exit

The shared Inertia error handler suppresses recognized transport rejections and resets poll coalescing. In-flight prefetch visits are tracked and settled on transport failure so failed entries purge from the cache without unhandled rejections.

The `networkError` listener in `coalesceReloads.ts` checks `isTransportError`
to cancel Inertia's default promise rejection on `HttpNetworkError` or
`ERR_NETWORK` via `event.preventDefault()`. Resetting reload coalescing maps
allows another poll while preserving error visibility for non-transport defects
without automatically replaying writes.

Inertia invokes its internal prefetch error cleanup only when the global
`networkError` event remains uncanceled. Canceling the event therefore risks
leaving failed prefetches in the in-flight cache with unresolved promises,
hanging subsequent navigation to that destination. To prevent this,
`coalesceReloads.ts` tracks prefetch lifecycles by registering a `prefetching`
event listener that maps active visits by ID, while `finish` and `error`
listeners unregister them upon completion.

When a transport failure occurs, any active prefetch entry has a silent
`.catch(() => {})` attached to its in-flight `entry.response` promise to prevent
unhandled transport rejections. The visit's `onPrefetchError` callback is then
invoked with `HttpCancelledError` for transport failures (or the original error
otherwise), triggering Inertia's internal cache eviction without its
`prefetchedRequests.add` catch chain re-throwing an unhandled rejection.
Subsequent navigation to the same URL initiates a fresh request that completes
cleanly.

### Why the theme-layout Suspense fallback reuses the same shapes

Bill, BillOfTheMonth and Bills pick their layout from the reader's theme, so it loads separately and needs its own Suspense fallback — a second, narrower gap than the round-trip placeholder above.

This gap opens only for the layout module, after the page has already mounted.

[[app/frontend/components/bill/ThemeLayoutPlaceholder.tsx]] fills that gap by rendering `DetailShape` or `ListShape` from `app/frontend/navigation/shapes/` directly, rather than a third markup shape: those two already match this content (the registry maps `/bills/:id` and `/bill_of_the_month` to `detail`, `/bills` to `list`), and a reader who sees the round-trip placeholder then the layout-load placeholder sees the same shape hold still rather than swap.

Unlike the round-trip placeholder, this fallback has no `PageBodySlot` around it to carry the accessible announcement, so it wraps the shape in its own `<output aria-live="polite">` with `sr-only` text.

What the signed-in layout asks the browser to fetch while it is idle is
[[legislator-photo-prefetch]].

### Why the outgoing page is not painted under the placeholder

The outgoing page and the placeholder share one grid cell, so the reader has to be given one of them, not a blend. While a placeholder is up the outgoing region drops to zero opacity; a dim with no placeholder leaves it legible.

The first shipped version dimmed to 0.4 in both cases. Stacking a 40% page under a pulsing skeleton left headings and card edges reading straight through the blocks, which says "half loaded" rather than "loading" and is harder to look at than either state alone. Two utilities carry the split: `nav-replaced` for the covered case, `nav-leaving` for the bare dim. Both fade over `--dur-1` rather than cutting.

The element stays in the layout rather than being removed, so the document keeps its height and scrollbar for the length of the visit. Collapsing it would move the page under a reader who is already waiting, and the arriving page resizes it once anyway.

The rule is keyed to the placeholder rather than to `dim`, because what it encodes is that nothing paints under a skeleton. The two flags agree today; the divergence anticipated for partial reloads is a dim with no placeholder, which this leaves dimmed and readable.

### Why the placeholder's corners are twice the component radius

A placeholder block stands in for a component without being one, so it is rounded softer than anything it replaces: `calc(var(--radius-md) * 2)`.

Multiplying the theme's own radius rather than setting a length is what keeps the rule honest across themes. `cornerstore` and `ballot` are deliberately square-cornered, and a fixed radius would round their skeletons while every real control on the page stayed sharp; doubling leaves zero at zero and scales with each theme's own softness. On the thinnest blocks the browser clamps the radius to half the height, which is why a line skeleton reads as a lozenge in the rounder themes.

### Why focus moves to the slot's status region

Applying `inert` to an ancestor of the focused element blurs it to `<body>`, and every primary navigation here starts from inside the treated region. A keyboard reader would otherwise lose their place for the whole load, with nothing to restore it.

Bill rows, legislator cards and the Legislators call to action all sit inside that region, and Inertia does not restore focus on a page change.

The slot remembers the last focused element and, on entering the treatment, moves focus to its own status region when that element was inside the region going inert. Focus is never taken from a control outside it, so a reader who moved to the drawer keeps their place. The remembered element is the primary signal because `document.activeElement` by then says `<body>` and no longer says where focus came from, and the outgoing container is excluded from it, since the hand-back parks focus there and containment would otherwise be satisfied forever after the first navigation.

The live `document.activeElement` is a second admissible signal, admitted only when it is the outgoing container itself. That is the one position the remembered element cannot distinguish: the hand-back parked focus on the container, and a reader who starts the next navigation without moving focus first — the browser Back and Forward buttons, or a mouse click on a link in Safari or Firefox on macOS, neither of which moves focus to a clicked link, which is documented behaviour of those browsers rather than something measured here — would otherwise be dropped to `<body>` for the whole load. The announcement is unaffected either way; what is lost without this branch is the focus position.

The status region is the slot's first child because sequential focus order follows DOM order: written last, the reader's next Tab would leave the slot entirely and skip the page that just arrived. It is `sr-only`, so its position changes nothing on screen. On clear, focus goes back to the outgoing container — the one element that survives every page swap — rather than the new page's heading, which may not be committed yet.

### Why the slot pins grid-cols-1 and min-w-0

Both layouts route every page body through this slot, so its sizing rules apply to the whole app. A bare `grid` gives an implicit `auto` column and every item an implicit `min-width: auto`, flooring each at its max-content width.

That floor made the admin testimony report lay out 832px wide at a 320px viewport and scrolled the page sideways. `grid-cols-1` sets the track minimum to zero and `min-w-0` lifts the per-item floor; dropping either reintroduces the overflow, which `spec/system/admin_testimony_report_layout_spec.rb` catches.

### Why the crossfade is cancelled rather than shortened under reduced motion

The root view transition is timed off `--dur-2` with a literal fallback, so a renamed token cannot silently drop the crossfade to the browser default. A `prefers-reduced-motion: reduce` block removes the animation outright rather than shortening it.

Neither rule is reachable from jsdom, which has no view-transition pseudo-elements, so both are proved by parsing `application.css` — the same seam the placeholder fill's contrast floor uses. Nothing else asserts them, and a deleted reduced-motion block would be an accessibility regression no other gate catches.

## Why the shell keeps one reading measure

`AuthLayout` swaps the drawer for a fixed 18rem sidebar at `lg:` and caps every page body at `--content-max`, 800px in the sway theme. A wider display gets wider gutters, never a longer line.

`--content-max` is a reading measure rather than a leftover. A longer line of body text is harder to return from at the end of each line, so the cap holds however wide the display is, and nothing in the shell widens a page above `lg:`.

The bill page was once the exception. Above 1280px it seated the vote panel in a 20rem track beside the reading column, through a `data-page-width="wide"` marker on its root that `AuthLayout` matched with `has-[]` to widen its two caps. The panel was the only thing that column ever held, and a control at the edge of the page is exactly what read as an afterthought; the arrangement was retired when the ballot moved into the hero ([[user-vote-submission#Themed web vote controls#Where the default control sits]]). No page carries the marker now.

Browser specs that need a particular viewport set it through `NarrowViewportHelpers#with_narrow_viewport` and navigate through `#visit_narrow`, the same helper the 320px specs use, rather than inheriting the driver's 1400x1400 window. Those two take a width and a height, so the "narrow" in the name is the default rather than a limit, and the DevTools metrics override behind them is the only seam that sets the layout viewport itself. `#visit_narrow` measures `window.innerWidth` after the navigation, because an override that stopped applying would hand an example a viewport nobody asked for and a wide example would pass on the window's own width.

## SQLite as the primary store

The primary database is SQLite in WAL mode, not Postgres. For a workload whose
writes are individual votes and whose reads are aggregate tallies, a single
file on local disk removes an entire tier from the deployment.

One follow-on decision shapes everything else: SQLite allows a single writer at
a time, so anything that writes on a schedule of its own is moved off the
primary file rather than allowed to contend with a vote. Four database files
follow from that.

The development environment enforces the same single-file assumption. Databases
live in the `sway_storage` Docker volume, and `config/boot.rb` refuses to start
Rails directly on the host, because a host process would silently open a
different, empty `storage/` directory.

What the four databases hold, and how each is provisioned, backed up and
kept out of test, is [[auxiliary-databases]].

## Work that outlives a request

Registration, scoring, summary generation, notification fan-out and the
pipeline all run as jobs, in a consistent shape: a model commit enqueues a job,
the job calls a service object, and the service object owns the transaction.

`UserVote` is the clearest instance — `after_create_commit` enqueues
`OnUserVoteUpdateScoresJob`, which runs `ScoreUpdaterService`, which wraps
`ScoreRecomputeService` in one transaction. The write path stays fast, and the
expensive recomputation is retryable. Why that recomputation is a full rebuild rather than an increment is covered by
[[scores-and-agreement#Scores are recomputed, never incremented]].

## Keeping scores fresh

Score freshness is a hybrid, not a single mechanism. `ScoreUpdaterService`
broadcasts on an ActionCable channel keyed to the voting user; the browser's
[[app/frontend/hooks/useScoreSubscription.ts#useScoreSubscription]] answers
that push by reloading only the score props.

A push alone would be fragile — a dropped socket would leave a stale tally on
screen with nothing to correct it. User-facing pages therefore also carry
`usePoll(15000)` as a floor. Admin surfaces that watch an in-flight pipeline
poll tighter, at five seconds, because an operator is actively waiting on stage
transitions there.

Every one of these reloads passes `preserveScroll: true`. Without it, a
background refresh would jump a reader to the top of a bill they were part-way
through.

### Two refreshes of one page collapse into one

The push and the poll answer the same score change, so a page can ask the
server for the same props twice within a moment.
[[app/frontend/navigation/coalesceReloads.ts#handleBeforeReload]] drops the
second of those, inside a two second window.

It listens on the router's `before` event, which every Inertia visit passes
through — a category toggle and a search box use partial visits too, and
dropping one of those strands the reader on a list that no longer matches the
controls above it. Three conditions therefore have to hold before a visit is
treated as a duplicate, and any visit failing one of them is always sent:

- The visit is a `GET`, and not an initial deferred-prop fetch (`deferredProps: true`). A write means the next read is not a repeat of the
  last one: the enable-push button posts a subscription and then reloads the
  same prop it was already showing, and that reload carries the new row.
  Any non-`GET` visit or non-prefetch full-page `GET` navigation empties the window for the same reason, and Inertia's `loadDeferredProps` requests bypass coalescing altogether because cancelling a one-shot deferred prop fetch strands `<Deferred>` on its fallback indefinitely.
- The visit asks for the same props, on the same path *and query string*. A
  filter change moves only the query string, so keying on the path alone made
  `?categories=Housing` and the unfiltered list one page.
- The visit targets the address already on screen. That is what a refresh is,
  and it is all `router.reload` ever does; anything else is a navigation, and
  a navigation to a page the reader left seconds ago is a deliberate return,
  not a duplicate.

Each condition fails open — an unrecognised URL shape costs a redundant fetch,
never a missing one.

## Surfaces beyond the browser

Four other surfaces read the same models: dual-rendered JSON, the `/api/v1`
mobile namespace, a handful of ERB pages, and ActionCable.

The two JSON paths are easy to conflate and authenticate differently.
Dual-rendered JSON answers one controller action as either an Inertia page or
a JSON body, on the session the browser already holds. `/api/v1` is separate,
carries a bearer token, and trusts no cookie at all. The ERB pages exist
because they must work with no React bundle, and ActionCable carries the score
and pipeline pushes.

`app/controllers/api/v1/` is the mobile namespace, and the reason certain
serializer keys are frozen against renaming. The ERB set is small and
deliberate — the mobile download page, the associated-domain files, the
sitemap. [[surfaces#Delivery surfaces]] maps all five.

The mobile app is a separate pnpm workspace under `mobile/`, deliberately
confined to free-tier Expo: builds run locally through `eas build --local`.

## Deployment

Deployment is Kamal onto a single arm64 Raspberry Pi, behind Caddy and a
Cloudflare tunnel, with two web containers and one job container. Some traffic
never reaches that machine: [[cloudflare-edge-rules]] explains what the edge
drops.

That machine is the reason the pipeline was brought back into Rails rather than
kept as a Python sidecar, and the reason the LLM provider is pluggable rather
than assumed. [[legislation-pipeline#Why it runs inside Rails]] and
[[llm-summaries#Two adapters, one client]] cover both.

### An open page pings the health check to stay inside the idle window

A page left open asks for `/up` every 4.95 minutes, which is just under the
five-minute idle window.

The interval is set below the window rather than at it so that a ping always
lands inside it, whatever the round trip costs on the day. A ping exactly on
the boundary would be a race the page loses whenever the request is slow, and
losing it means the reader's next interaction pays for a cold start.

### The release fingerprint never runs a diff converter

`scripts/uncommitted_digest.sh` fingerprints the working tree with
`git diff HEAD --no-textconv`, so no `.gitattributes` converter can run during a
deploy.

Rails ships a `diff=rails_credentials` attribute for `config/credentials.yml.enc`
whose textconv is `bin/rails credentials:diff`. Booting Rails on the host is
refused by `config/boot.rb`, so once that file is edited and left uncommitted,
git reports `fatal: unable to read files to diff` and the whole deploy aborts on
exit 128 — with a message about Rails that names nothing about deployment.

Hashing the stored bytes is also the behaviour the fingerprint wants. A
converter's output is not what ships in the image, and decrypting a credentials
file to feed a digest would put its plaintext on a pipe for no gain.

### The version page has three answers, not two

Whether a build is the commit it names has a third answer besides yes and no:
nobody recorded it.

Only a deploy writes that flag, so a null means the question was never asked
rather than answered in the negative. Reading a null as true would let a page
claim a clean tree while it is being edited, which is the one reading that
misleads. A non-null uncommitted digest is the positive form of the same fact:
the image also carries changes that were never committed, so the commit it
names cannot rebuild it.

### The logo tooltip includes the running build

[[app/frontend/components/brand/ReleaseInfo.tsx]] shows shared release metadata beside the Sway logo on every screen.

Its build label distinguishes a clean commit, a commit plus uncommitted changes, and a build with no recorded status. The selectable commit SHA and deployment time help identify what is running. [[app/frontend/pages/Version.tsx]] exposes the same metadata through a permanent link for touch devices where the logo tooltip is not available.

The development-only user row appears only when a phone number is present. Guests have a null user prop, so omitting the row keeps the shared logo tooltip usable on public pages.

## Auth navigation

The shared page shell switches navigation for administrators on admin routes. Reader navigation keeps public discovery separate from account membership, while both modes use the same sign-out handler.

Admin context matches the exact /admin path or a child path after removing query and fragment text. Tool prefixes keep their navigation item active on deeper pages. Admin secondary navigation offers Back to Sway, Passkeys, Sign Out and GitHub; reader notifications and organization links stay on the reader surface.

The switch turns on two conditions together — the address namespace and the account's admin role — so a break in the address check alone would leave the navigation looking right for the people who test it. That is what the layout's own regression examples pin.

Browse Organizations is public discovery; Organizations opens the account's memberships. Reader primary navigation separates Past Bills of the Month (`/past_bills_of_the_month`) from All Bills (`/bills`), so featured monthly history and full legislative session browsing have dedicated entries. Guests can discover organizations before signing in. A shared sign-out item keeps error handling consistent across both navigation modes. One page-state read supplies the route and shared props. The named AuthLayout export supports direct navigation tests; its default adapter accepts an Inertia page element.

Signed-in readers and administrators have a Passkeys link in [[app/frontend/components/layouts/AuthLayout.tsx#AuthLayout|the shared navigation]]. The desktop sidebar and mobile web drawer use the same items, making [[identity-and-access#Identity and access#The admin gate is a lint rule#Adding a passkey re-verifies by SMS first|authenticated enrollment]] reachable without knowing its URL. Guests do not see the account link.

The offline notice spans the content column so its warning background covers the text. It preserves already rendered content and offers dismissal in its initial state. Its polite live region tells readers to reconnect to load pages and vote, without promising cached page access. The browser cache policy lives in [[client-caches-and-identity#Client caches and identity]].

## Why CspReportsController filters extension violations and normalizes report payloads

[[app/controllers/csp_reports_controller.rb#CspReportsController]] filters browser-extension violations, normalizes both legacy and Reporting API payload shapes, and samples Sentry forwarding so extension noise and payload differences do not flood error tracking.

Browser extensions inject scripts from extension schemes (`chrome-extension`, `moz-extension`, `safari-extension`, and `safari-web-extension`) that trigger Content Security Policy reports unrelated to application assets. Because browsers submit either a single `csp-report` object or a `reports+json` array with camelCase keys, the controller normalizes both formats and wraps array payloads in a Hash before calling `Sentry.capture_message` so `Sentry::Scope#set_extras` receives a Hash.
