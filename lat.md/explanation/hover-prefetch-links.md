---
lat:
  mode: explanation
---

# Links that warm before the click

Some links fetch their destination before the reader opens it, so the page is already in the browser when the click lands. Two moments start that fetch: a hover over a link rendered once per page, and a mousedown on a link repeated per row.

`PREFETCH_CACHE_FOR` in `app/frontend/sway_constants/navigation.ts` is the cache window, exported as the stale-while-revalidate tuple `['30s', '5m']` rather than a literal per call site. An earlier pass stated the value at two of the five sites and left three inheriting it, which is worse than stating none: the next editor changes the visible two and leaves the rest behind.

The warming is bounded inside `@inertiajs/core` rather than in this app. A request for parameters already in flight returns early, so two links pointing at the same address warm once between them. Requests within the 30-second fresh window return immediately from cache without a network call, while requests between 30 seconds and 5 minutes render immediately from the stale cache and revalidate in the background. Beyond 5 minutes, the cache entry expires and subsequent navigation fetches a fresh page from the origin.

## Which links warm on hover and which on mousedown

The moment follows how many times a link is rendered. A link the page renders once warms on hover; a link repeated once per row of a list warms on mousedown, which happens only on the row a reader presses.

Four warm on hover, and every one of them is rendered once per page: a drawer navigation item whose `prefetch` flag is set, the brand link at the head of the drawer, the sponsor of a bill, and the Start voting link in the header of the representatives page. A reader crossing one of those produces at most one request, and the hover starts it far enough ahead of the click to save the whole round trip.

Five are repeated per row and warm on mousedown instead: the bill row link — every list, card or record row that links to a bill, including the Bill of the Month voting record on a legislator page — both links on an organization card, the View Organization button on a membership card, and the View representative button on a legislator card. `@inertiajs/core` accepts `mount`, `hover` and `click` as the moment, and `click` starts the request on `mousedown`, before the button is released, so a click still consumes a warmed response while a pointer that merely crosses the row produces nothing.

Hover on a list row was the earlier behaviour, and it asked for more than the origin had to give. A bill list holds 24 rows, and five readers passing across all of them at once produce more requests a second than the whole web role can answer. Mousedown drops the passing reader out of that arithmetic and keeps most of the saving, because the gap between pressing a mouse button and releasing it is long enough for a request to be under way.

## Why the sponsor link is one component

The sponsor of a bill is the natural next click from the busiest page on the site, and its destination — the legislator page — was already proven safe to warm by the legislator cards.

That link is rendered from four places: `BillHeader` for the default theme, and the Ballot, Banner and Corner Store layouts. Three of them built the address by hand as a template string rather than through `ROUTES.legislator`, and none carried prefetch. A decision that has to land in four places lands in three.

`BillSponsorLink` holds the address, the prefetch moment, the cache window and the crossfade, and the four call sites pass only the legislator id, a class name and the link text. This is the same consolidation `BillRowLink` made for the bill rows, for the same reason: one edit rather than four when the decision changes. It warms on hover because a bill page carries one sponsor link, not one per row.

## Which organization links warm, and which stay cold

The organization screens repeat a card per row, and the card's own link is what a reader clicks after scanning. Three of them warm on mousedown: the organization name, the View button beside it, and the View Organization button on a membership card.

The "View bill" link inside a position card goes through [[app/frontend/components/bill/BillRowLink.tsx#BillRowLink|BillRowLink]] rather than carrying the attributes itself, because it is a bill row link like any other and gets the crossfade along with the warming. So do the bill links on the reader's own membership page, in `PositionCard` and `PendingChangeCard`, which built the address as a template string and warmed nothing. [[app/frontend/components/bill/BillRowLink.tsx#BillRowLink|BillRowLink]] builds every warmed bill-row link, while home-feed bill cards ([[app/frontend/components/feed/FeedBillBlock.tsx#FeedBillBlock|FeedBillBlock]] and [[app/frontend/components/feed/FeedBillActions.tsx#FeedBillActions|FeedBillActions]]) render cold `<Link>` elements so following one hits [[app/controllers/bills_controller.rb#BillsController#show|BillsController#show]] without `Purpose: prefetch` and records a [[app/models/bill_view.rb#BillView|BillView]] via [[app/controllers/concerns/records_bill_views.rb#RecordsBillViews#record_bill_view|record_bill_view]].

The back-to-list link at the top of an organization page stays cold. It points at `/public/organizations`, a destination the reader has almost always just come from, so warming it would spend a request on a page the browser already holds.

Warming only saves a round trip when the address warmed is the address opened. None of these pass `only`, `data` or headers that would vary the request, so the warmed response is the one the click consumes rather than a second fetch alongside it.

## What the warming costs the origin

Warming a bill row is a whole page request, so hover prefetch multiplies the requests one reader produces and the origin's capacity limits how much warming is safe.

The bill list answers faster than a bill page because its rows are a deferred prop. Warming the list fetches the shell; the rows arrive in a second request that the warming does not make.

### The volume one bill list produces

`BILLS_INDEX_PAGE_SIZE` is 24, so a reader passing over every row of one page produced 24 requests while the rows warmed on hover.

Each dwell was longer than the 75 millisecond delay `@inertiajs/core` applies before a hover fires. Several readers sweeping at once multiply that figure.

`PREFETCH_CACHE_FOR` cannot widen the headroom. Both the cache window and the in-flight de-duplication act on a repeated address, and a sweep across 24 distinct rows repeats none. Warming the rows on mousedown removes the sweep from the figure instead: a reader who passes over 24 rows and presses one produces a single request rather than 24.

A signed-in reader's warming request costs more than a signed-out one, because it adds a session lookup and a per-user vote join.

## Why jurisdiction switching flushes the prefetch cache

Switching jurisdictions clears in-memory prefetch entries so navigation links warmed under a prior locale cannot serve stale content.

Drawer navigation links (`/bills`, `/legislators`, `/bill_of_the_month`, `/organizations`) use bare destination paths without query parameters, relying on the session cookie to determine jurisdiction. When a reader hovers over a link, Inertia stores the rendered page in its prefetch cache for up to five minutes. When the user selects a new jurisdiction in `useSwayLocale`, `getSwayLocale` invokes `router.flushAll?.()` immediately before dispatching the `router.get` visit. This eviction prevents the browser from displaying legislation or representative rosters from the previous jurisdiction when the user subsequently follows a warmed link.

