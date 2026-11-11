---
mode: explanation
summary: "Why the navigation-placeholder gate, store and registry are shaped the way they are — the six gate conditions, the before/finish|success|error wiring and its watchdog, and the registry's no-page-import rule."
status: agent-extracted
related: []
---

# Navigation placeholder tracer

## Why `qualifiesForPlaceholder` checks six fields

Each condition catches a specific real call site the app makes, verified against the
installed `@inertiajs/core` source rather than assumed:

- `only`/`except` empty excludes every `router.reload({ only: [...] })` background
  refresh (score sync, Bill Creator polls, `RunSelector`'s partial GET).
- `prefetch === false` keeps a hover-warmed speculative request silent.
- `async === false` and `preserveState !== true` are the two conditions that catch a
  **bare** `router.reload()` — `doReload` force-sets both regardless of caller options,
  which is exactly the shape `usePullToRefresh` uses on `Bill.tsx` and
  `BillOfTheWeek.tsx`. Trimming either ships a full-page grey strobe on pull-to-refresh.
- `method === "get"` excludes every form submission (Inertia already forces
  `preserveState: true` on POST/PUT/PATCH/DELETE, so condition 5 would catch these too,
  but stating the method explicitly matches the design decision's own language).
- `url.href !== currentHref` excludes a self-navigation. It compares the full href
  rather than the pathname, so a locale switch that changes only the query string still
  qualifies where it is a full visit (`BillOfTheWeek`), but it strips the fragment
  first — the same `urlWithoutHash` normalisation `Router#visit` applies one line later
  in its own same-page test. Comparing the raw href instead treated a hash-only change
  as a full navigation: on `/bills#top` a `<Link href="/bills">` (the drawer's own
  `/bills` entry among them) drew a full skeleton and marked the body `inert` for a
  visit Inertia itself resolves as same-page, and an in-page anchor did the same in
  reverse.

## Why `qualifiesForDim` is a plain delegation, not a wider predicate

The roadmap's own motivating example (locale switch on the Bills page) is a partial
reload and is excluded by the gate above. Widening `qualifiesForDim` to admit
that case (via a stated visit marker) was considered and rejected: the locale
picker lives inside the treated region, and marking that
region `inert` while it holds the focused control would strand a keyboard or
screen-reader reader for the duration of the switch, because `preserveState: true`
means nothing remounts and Inertia's own focus handling never runs. A stale-content
treatment for partial reloads is a different treatment with a different focus
contract, filed separately rather than folded in here. The two predicates stay
separate functions because dim and placeholder answer different questions and are
expected to diverge later, even though they do not yet.

That "not yet" has a cost worth naming. Because the two predicates return the same
answer today, the store can never produce a state with `dim` raised and `placeholder`
null through any real event, so four consumers written as if the two could disagree —
`navigationStore`'s `if (!dim && !placeholder)` guard and its two
`placeholder ? … : null` expressions, and `PageBodySlot`'s `Boolean(placeholder) || dim`
and `pageName ?? "page"` — describe a shape nothing exercises. Untestable branches rot,
and the gate table cannot help: asserting `qualifiesForDim` against all eighteen rows
only re-asserts `qualifiesForPlaceholder`.

The consumers are kept rather than collapsed, because collapsing them would contradict
the decision above and make the eventual divergence a rewrite instead of a one-line gate
change. What is added instead is coverage: `PageBodySlotDivergentState.test.tsx` stubs
the store and renders the slot with `{dim: true, placeholder: null}` directly, which
reaches every one of those branches and pins what the slot promises for that state —
inert and dimmed with no skeleton, still `aria-busy`, announcing "Loading page" when no
page name came with the dim.

## Why the store sets on `before` and clears on three attributed events

A navigation that consumes a prefetch entry — cached or still in flight — never
creates a `Request` object, so it fires neither `start` nor `finish`. On a slow link a
click routinely beats an in-flight hover prefetch home, which is the network this
phase is judged at. Setting on `before` covers every path, including that one.
Clearing on `finish` OR `success` OR `error` means all three write the same idle
value, so order and duplicates cannot matter.

## Why the clear is keyed to the visit that raised the treatment

An earlier version of this store cleared on any of those three events without asking
which visit the event belonged to, on the reasoning that a second visit interrupts the
first inside `visit()` before its own request is created, so the earlier visit's clear
would always land before the later visit's set. The installed library does the
opposite. `Router#visit` fires `before` first, and only afterwards cancels what is
already in flight:

```js
if (events.onBefore(visit) === false || !fireBeforeEvent(visit)) {  // our handler sets state here
  return
}
if (!isSamePage) {
  this.asyncRequestStream.cancelInFlight({ prefetch: false, optimistic: false })
}
if (!visit.async) {
  this.syncRequestStream.interruptInFlight()
}
```

Both cancel paths reach `Request#cancel` → `fireFinishEvents()` → `fireFinishEvent()`,
and `fireEvent` dispatches on `document` synchronously. So the new visit's own `before`
raises the treatment and is then immediately followed by a `finish` belonging to some
*other* request — every `usePoll` / `useScoreSubscription` `router.reload()` that
happened to be outstanding, or an interrupted earlier navigation. Without a guard the
reader gets no placeholder, no dim and no announcement for the whole of the load, and
the failure gets more likely the slower the link is, because a poll response is
outstanding a larger fraction of the time.

`handleBefore` therefore records `visit.id`, and `clearFor` ignores any clear carrying
a different id. `finish` carries `detail.visit`; `success` and `error` carry
`detail.visitId`.

## Why `networkError` and `httpException` shorten the bound instead of clearing

Neither event carries a visit id, and both fire for background requests as readily as
for the navigation. `Request#send`'s catch reaches `fireNetworkErrorEvent` for anything
that fails at the transport layer, which includes a `usePoll(15000)` or
`useScoreSubscription` reload; `httpException` fires for any response at status 400 or
above, the same way. An earlier version cleared unconditionally on both, so clicking a
link while a poll was outstanding and losing that poll's connection took the
placeholder, the dim, the `aria-busy` and the announcement away for the rest of the
load — the same failure the visit-id guard above exists to prevent, narrowed to a flaky
link, which is the population this phase exists for. `httpException` had a second case:
in `Response#process` it is fired *before* `await history.processQueue()` and `await
this.setPage()`, and `setPage` can await a code-split chunk download, so an error-status
Inertia response un-`inert`ed the body while the destination was still downloading.

The unconditional clear could not simply be deleted, because it is load-bearing for one
real case: a click that consumes an in-flight prefetch whose own promise then rejects,
where the clicking visit's id never reaches any event at all. Both listeners therefore
re-arm the watchdog at `NAVIGATION_TREATMENT_UNATTRIBUTED_MS` (3 seconds) rather than
clearing. The stranded case is still rescued, three seconds later instead of instantly,
and a live navigation survives a background failure. A failure arriving with no
treatment up is ignored outright.

## Why the treatment carries a watchdog timer

A visit that consumes a hover-prefetched entry never builds a `Request`, so it has no
`.finally(() => this.finish())` backstop — `PrefetchedRequests#use()` calls
`response.handle()` directly. `Response#process()` then has three branches that return
without firing `finish`, `success`, `error` or `networkError`:

- `handleNonInertiaResponse()` where `onHttpException(response)` returns `false`.
- `handleNonInertiaResponse()` where `fireHttpExceptionEvent(response)` is not
  cancelled and the library shows its own error dialog — a 500 HTML error page, a proxy
  interstitial, an expired-session HTML redirect target.
- `PrefetchedRequests#use()`'s own `if (this.currentUseId !== id) return`.

Without a backstop the store never leaves the placeholder state, and `PageBodySlot`
keeps `inert` on the outgoing region: the reader is left looking at a frozen skeleton
with no interactive page body, outside `PageErrorBoundary`, with no way back except a
hard reload. Hover prefetch is on every bill row, drawer item and legislator card, so
this is the common path rather than a rare one.

The watchdog — a timer reset on every state change and armed whenever the state is not
idle — bounds all three, and anything else the library grows later. The `httpException`
listener shortens that bound for the second branch rather than clearing on it, for the
reason given in the section above.

The bound has to clear a legitimate slow load by a wide margin, because when the timer
wins mid-navigation the treatment simply vanishes: the placeholder goes, `inert` is
lifted, and the reader gets the interactive *stale* page back with no indication that a
load is still running, until it swaps under them. An earlier value of 20 seconds did not
clear that margin. `navigation_placeholder_spec.rb` waits `have_css("h1", text:
"Organizations", wait: 20)` twice on `ServiceWorkerStub#go_slow_link!`, the same
throttled profile this phase is judged at, so the spec author's own budget for a
legitimate load on that link was the whole of the bound rather than comfortably under
it, and on a 2G-class link well below `go_slow_link!`'s 24 kB/s expiring mid-navigation
would have been the normal outcome rather than the exception. Sixty seconds is three
times that measured budget and is still an unmistakable strand rather than a load
anyone is waiting through.

That argument only weighs one direction, and the other direction grew after it was
written. Since the focus rescue landed, the treatment does more than cover the page: it
holds `inert` on the whole page body and parks keyboard and screen-reader focus on a
nameless, empty `sr-only` region for as long as the treatment is up. So the bound is
also the bound on how long a reader can be left with no interactive page body and
nowhere useful to be, and raising it from 20 seconds to 60 tripled that worst case. The
strand is silent as well as long — the announcement says "Loading" and never changes.

The trade still favours 60 seconds, because the three abandoned branches listed above
are not equally reachable:

- The `onHttpException(response) === false` exit cannot be reached in this app at all.
  Nothing passes an `onHttpException` option, and the library's default is `noop`, which
  returns `undefined` rather than `false`.
- The error-dialog exit fires `httpException` on the line before it returns, so the
  3-second shortcut in the section above bounds it.
- `PrefetchedRequests#use()`'s `currentUseId !== id` is the one that can still ride the
  full 60 seconds, and only when the visit that superseded it did not itself qualify for
  the treatment — a qualifying successor re-arms the timer under its own visit id and
  then clears normally.

Lowering `NAVIGATION_TREATMENT_MAX_MS` is the wrong lever if that residual is ever judged
too long, because below about 20 seconds it collides with the spec's own `wait: 20` budget
for a legitimate slow load. The structural fix is to split the bound: release `inert` and
the borrowed focus on a short bound, and leave the placeholder and the announcement up to
the full 60.

## Why `placeholderRegistry.ts` imports no page component

The placeholder must be pickable from the destination address alone, before the
destination's code-split chunk downloads. Importing a page component — or anything
that transitively reaches one — would put the placeholder behind the very download it
exists to cover.

## Why `PLACEHOLDER_ENTRIES` is ordered most-specific-first

`resolvePlaceholder` returns the first matching entry, so a broad prefix placed above
a narrower one silently steals its addresses — `/admin` above `/admin/locales` would
resolve every admin sub-page to the dashboard shape instead of settings. Each pattern
is written as either an exact string comparison or an anchored regular expression
literal in the source (never `new RegExp` built from the incoming pathname, never a
dynamic `import()`), so the registry stays free of anything that could execute or
resolve based on reader-controlled input — the injection threat a registry keyed by
the incoming pathname carries.

## Why `pendingVisitFixture` copies the router's own defaults object

The field list and default values in `pendingVisitFixture` are copied from
`@inertiajs/core`'s own `getPendingVisit()` defaults
(`node_modules/@inertiajs/core/dist/index.js`, the `mergedOptions` and `visit` literals),
not written from memory, so the fixture cannot silently drift from what the installed
library actually sends. The path is written without a version, because the pinned version
moves; the pin itself is recorded once in `package.json` and checked by
`inertiaCoreVersionPin.test.ts`.

The trip wire for a future `@inertiajs/core` bump that adds or renames a `Visit` field
is the type annotation on the fixture's `BASE` object, and nothing else. Two earlier
candidates were tried and neither worked. `as PendingVisit` on the object literal is a
type assertion rather than a check — TypeScript permits missing properties as long as
the types overlap, so even `{} as PendingVisit` compiles. A `toBeGreaterThanOrEqual(28)`
assertion on the fixture's own key count measures the hand-written fixture against
itself: a new library field never changes that count, and a renamed one leaves it at 28.
Annotating `BASE` as `PendingVisit` with no cast puts the check where the compiler runs
it — `tsc` fails on the added or renamed field directly, so the key-count example was
deleted rather than kept alongside.

## Why `@inertiajs/core` is a pinned devDependency rather than a caret dependency

Every use of `@inertiajs/core` in this phase is `import type` — the gate, the store, the
fixture and `PageBodySlot`'s test all take `PendingVisit` and nothing else — so the
package contributes nothing at runtime and does not belong among the shipped
dependencies. It cannot be dropped entirely: `@inertiajs/react` re-exports only `http`,
`progress` and `router`, so there is no route to the type through the package we already
depend on.

The version is pinned exactly rather than left on a caret range because
`@inertiajs/core` holds module-level singleton state (`page`, `router`,
`prefetchedRequests`), and `@inertiajs/react` itself depends on an exact
`@inertiajs/core` version. Two independent caret ranges could resolve to different
minors, at which point the bundle carries two copies and `router.on` registers on a
router that never fires.

"Visible in review" was the original enforcement, and it did not hold. The pin was
written as `3.6.1`; `@inertiajs/react` was later bumped to `^3.7.0`, which brought its
own exact `@inertiajs/core@3.7.0`; the lock file duly carried both copies and nobody
looked. The bundle stayed safe — every app import of the package is an erased
`import type`, so only the react adapter's core reached the runtime and there was still
one router — but the guarantee the pin was bought for was gone, because the gate, the
store, `pendingVisitFixture` and `PageBodySlot.test.tsx` were all type-checking against
a `PendingVisit` that was not the one running.

`inertiaCoreVersionPin.test.ts` is the enforcement now: it reads the pin from
`package.json`, the exact `@inertiajs/core` version `@inertiajs/react` declares, and the
version actually resolved into `node_modules`, and asserts all three agree. The next
`@inertiajs/react` bump reddens the vitest lane instead of drifting quietly.

## Why the gate-table mutation check isolates condition 3 with a synthetic fixture

The two production call sites that reach `usePullToRefresh({ onRefresh: () =>
router.reload() })` (`Bill.tsx`, `BillOfTheWeek.tsx`) always carry `async: true` AND
`preserveState: true` together — `doReload` forces both regardless of caller options.
For that literal shape, conditions 3 and 5 are each independently sufficient to
exclude it, so removing only one from a mutated copy of the predicate would not
observably flip the literal production fixture. The mutation check therefore uses a
fixture with `preserveState: false` to isolate condition 3's effect: it proves
condition 3 alone is load-bearing against a background/async-shaped visit, which
complements — rather than duplicates — the table row that shows conditions 3 and 5
jointly exclude the real production shape.

## Why `navigationGate.test.ts`'s mutation check defines a second predicate locally

`withoutAsyncCondition` is identical to `qualifiesForPlaceholder` except it omits the
async check, so removing that one condition can be observed directly against a
fixture that isolates it from condition 5 (see the section above on the mutation
check's synthetic fixture).

## Why the two new CSS custom properties live in `application.css`, not a theme file

`--nav-leaving-opacity` and `--dur-placeholder-pulse` are app-level constants, not
theme identity. `token-contract.test.ts` requires every theme file to declare exactly
its contract's variable set — adding either property to one theme file turns that
test red.

Both are declared inside `@layer base { [data-theme] { … } }`, so both utilities read
them with a fallback matching that base value, the way `duration-fast` reads
`var(--dur-1, 140ms)` directly above. Outside a `[data-theme]` subtree — the
`public.html.erb` / `public.tsx` shell, or the window before the theme attribute is
applied — an unset custom property makes the whole declaration invalid at
computed-value time. Read bare, `opacity` would fall back to `1` (no dim at all) and
the `animation` shorthand would reset to `initial` (no pulse): both fail open and
silent, which is the hardest kind of failure to notice. `--dur-1` and `--ease-out` are
theme-scoped for the same reason and carry fallbacks in the same declaration.

## Why `placeholderRegistry.test.ts`'s row table mirrors `PLACEHOLDER_ENTRIES`' own order

The registered-pathname table in the test is written in the same most-specific-first
order as the registry's own array, rather than alphabetically or by shape. A broad
prefix entry placed above a narrower one silently steals its addresses (`/admin`
above `/admin/locales`, `/bills` above `/bills/12`), and that failure mode only shows
up in a table whose ordering can actually collide the same way the source does.

## Why the test enumerates one URL per `Pages` constant, in its own table

`app/controllers/concerns/pages.rb` is the authoritative list of every component a
visit can land on (25 constants at the time of writing, not the 31 a count
of page files implied). A separate table, one row per
constant, asserting none of them resolve to the generic shape, is what pins "a page
added to the server without a matching registry row" as a red test rather than a silent
gap: the registered-pathname table above pins the *content* of each entry, but nothing
in it would catch a server page that never got a row at all.

The first version of that table was a hand-copied mirror of `pages.rb` with a
`toHaveLength(25)` assertion, and it did not hold. Three constants — `PRIVACY`, `SMS`
and `TERMS` — were added to `pages.rb` after this phase's base commit and the test
stayed green, because nothing linked the copy to its source; the assertion pinned the
length of the copy, not the length of the list it mirrored. The test now reads
`pages.rb` at run time (the same way `contrast.test.ts` reads the theme files through
`themeFiles.ts`) and requires every constant to appear either as a URL row or in an
explicit exemption list. Adding a constant to `pages.rb` is now a decision the test
forces rather than one it can miss.

The exemption list exists because the public shell is genuinely a different app.
`PRIVACY`, `SMS` and `TERMS` render through `app/views/layouts/public.html.erb` and the
`public.tsx` entrypoint, whose `PublicApp` does not mount `PageBodySlot` at all, so
there is no treatment for them to be missing from. Exempting them states that; leaving
them out of the table silently would not.

## Why the six bill-row links route through one `BillRowLink` component

Five theme-specific list layouts plus the default card hold six link sites across five
files, with the chamber layout alone holding two. All six must carry the same hover-prefetch
and crossfade decision, and this phase is authorised to withdraw the crossfade if a
slow-link pass says it fights the placeholder. A withdrawal that has to
land in six places will land in four — `BillRowLink` makes it one edit instead.

## Which links carry the crossfade, and which also carry hover prefetch

"Every Drawer nav item" originally meant only the items `NavItemRow` renders from
`primaryItems` and `secondaryItems`. `DrawerBrand`'s `<Link href="/">` sits in the same
drawer, above the sections, and is a first-class way to reach Home, but carried neither
`viewTransition` nor `prefetch` — so the drawer crossfaded on every route except the one
its own logo points at. It now carries both, and the Drawer test covers it rather than
leaving the "every nav item" example asserting against a fixture that never included it.

`BillEditLink` takes the crossfade and deliberately not the prefetch. It renders beside
every `BillRowLink` in all five list layouts, so warming it on hover would double the
speculative request count of a list scan (see the hover-prefetch section below), and its
destination is an admin-only Bill Creator page that a reader scanning a list almost never
opens. The crossfade costs nothing until the link is actually followed; the prefetch costs
a full request on hover.

## What hover prefetch on every list row actually costs

Every bill row and every legislator card warms on hover. The upper bound is real: a reader
who drags the pointer down a fifty-row list can issue up to fifty `/bills/:id` GETs, each
running the whole `BillsController#show` action, and on the throttled link this phase is
judged at those speculative requests share a connection with the navigation the
placeholder is covering for. That is the cost, and it is accepted deliberately rather than
by omission — the point of the feature is that the row the reader actually clicks is
already home.

Two things bound it, both inside `@inertiajs/core` rather than in this app's code, which
is why they are worth writing down. `PrefetchedRequests#add` returns early when a request
for the same parameters is already in flight, so the two `BillRowLink`s per entry in
`ChamberBillListLayout` (the title and the "Read →" affordance, both pointing at the same
href) warm once between them, not twice. It returns early again on a cached entry that is
not yet stale, so re-hovering a row costs nothing.

The window for that second check is `cacheFor`, which defaults to 30 seconds. All five
hover-prefetch call sites pass it explicitly, from one exported constant
(`PREFETCH_CACHE_FOR` in `app/frontend/sway_constants/navigation.ts`): `BillRowLink`,
`LegislatorCard`, `NavItemRow` and `DrawerBrand` in the drawer, and the Legislators page's
"Start voting" button. The value is unchanged; stating it means the lifetime of a warmed
row is visible at the call site instead of inherited invisibly from a library default, and
a change to it is one diff rather than a silent shift.

It is one constant rather than five literals because an earlier pass stated the value at
two of the five and left three inheriting it, which is worse than stating none of them: the
next editor changes the two that are visible and leaves three behind, which is exactly the
failure stating it was meant to prevent.

The measured request count for a real list scan has not been taken. The 69-06 slow-link
pass measured the placeholder, not the prefetch fan-out, so the bound above is reasoned
from the code rather than observed. Restricting `prefetch="hover"` to above-the-fold rows,
or moving list rows to `prefetch="mount"` over a capped slice, are the levers if a
measurement later says the fan-out is worth cutting.

## Why the crossfade's reduced-motion rule can't join the existing block

`application.css`'s existing `prefers-reduced-motion` block is scoped to
`[data-theme] *`, matching descendants of the themed root element in the normal DOM
tree. The `::view-transition-old(root)`/`::view-transition-new(root)` pseudo-elements
the crossfade animates live in the document root's own pseudo tree, which that
selector does not reach — so a reader who asks for reduced motion still gets the
crossfade unless a second rule targets those two pseudo-elements directly.

## Why the pulse keyframes moved from 12%/20% to 16%/24%, and resting stayed at 16%

The pulse was first specified as the `color-mix` percentage oscillating
12% → 20% around a 16% resting value, with a 1.20:1 contrast floor. Measured
against every shipped theme's own `--muted-foreground` and `--background`
(that floor, against the raw background), the 12% low end falls short in five
of six themes — `banner`, `chamber`, `classic`, `cornerstore` and `sway` all
measure between 1.16:1 and 1.19:1 at 12%, against the 1.20:1 floor. 16% and 20%
both clear it in every theme (worst case 1.227:1 and 1.295:1), so the fix keeps
the resting fill at the specified 16% and raises the pulse's low keyframe to
match it rather than dipping below — the pulse now brightens from 16% up to 24%
(chosen to preserve the original 8-percentage-point swing) and back, instead of
oscillating both above and below the resting value.

`contrast.test.ts` does not hold a copy of those percentages. It calls
`placeholderFillPercentages()`, which reads `application.css` at run time and
pulls every `color-mix(in srgb, var(--muted-foreground) N%` out of the
`placeholder-block` utility and the `placeholder-pulse` keyframes. An earlier
version wrote the numbers down a second time in the test, which meant a change to
either percentage left the floor green while measuring a colour the app no longer
painted — the same shape of hole `placeholderRegistry.test.ts` had when it
mirrored `pages.rb` by hand. Deriving them means a change to the stylesheet is a
decision the gate forces rather than one it can miss: the loop measures whatever
the app actually paints, so a percentage that drops below the floor reddens on
its own and one that clears the floor passes without needing a second edit.

The helper fails loudly rather than quietly when it can no longer find what it
reads — a renamed utility, a keyframes block missing its `0%` or `100%` stop, or a
stop declaring anything other than exactly one `--muted-foreground` mix all raise
rather than yield an empty set. Without that, a regex that matched nothing would
leave the loop with no mix to measure and every theme green.

## Where the placeholder fill's 1.2:1 floor comes from

`PLACEHOLDER_FILL_FLOOR` is the pulse specification's own number
and not a WCAG ratio — which is why it carries no citation of the kind every other
pair in `contrast.test.ts` has (`4.5` for body text, `3.0` for large text and
non-text indicators). WCAG's non-text minimum governs indicators that carry
meaning; the placeholder fill carries none, and holding it to 3.0:1 would make a
resting skeleton read as content rather than as absence. 1.2:1 is the point at
which the block is still distinguishable from the page behind it. Recording the
basis here is what stops a later editor lowering it as a nearby round number.

The measured table lists 16% once, as `"resting / pulse low (0%)"`. Those are the
same percentage — the pulse's low keyframe was raised to meet the resting value —
so listing them separately measured the identical mix twice per theme and let the
failure message name either label for one failure. The merge is conditional rather
than fixed: `placeholderFillPercentages()` compares the resting fill to the `0%`
stop it read and emits the joint label only while they agree, so a stylesheet that
moved one and not the other would be measured as three fills under three labels
instead of silently as two.

## Real-browser proof (Task 2, 69-06): why the drawer example forces a wide viewport

`navigation_placeholder_spec.rb` proves the placeholder against a real browser,
throttled with `ServiceWorkerStub#go_slow_link!`. The plan calls for asserting a
drawer link stays visible and usable while the placeholder is on screen — that
has to be the persistent desktop sidebar (`<aside>`), not the mobile drawer's
`Sheet`, because `NavItemRow`'s `onAfterSelect` closes the `Sheet` on the same
click that starts the navigation, and Radix unmounts `SheetContent` on close.
There would be nothing left to assert against by the time the placeholder shows.

Measured against the dip rspec image: the `selenium_chromium_headless` driver's
`--window-size=1400,1400` launch argument does not reliably set the layout
viewport — `window.innerWidth` measured 800px, below the `lg` (1024px)
breakpoint that shows the `<aside>`. `NarrowViewportHelpers#with_narrow_viewport`
already solves the equivalent problem at the narrow end of the range with the
same CDP `Emulation.setDeviceMetricsOverride` call the drawer example issues
directly at `width: 1400` in its own `before`/`after` pair, rather than through
the shared helper's block form: `with_narrow_viewport` yields around
`example.run` from an `around` hook, which — unlike a nested `before` — runs
before the outer `config.before(:each, type: :system, js: true)` hook has
switched the session onto the Selenium driver, so its `execute_cdp` call lands
on the default `rack_test` driver and raises `NoMethodError`. A `before`/`after`
pair sits at the same hook-ordering position as that global driver switch,
which is why the plain `go_slow_link!`/`go_online!` calls elsewhere in this
file (also plain `before`/`after`, not `around`) never hit the same failure.

The matching `after` rescues `Selenium::WebDriver::Error::WebDriverError` and
`NoMethodError` rather than using a bare `rescue`. The expected case is a
session already torn down by the time the override is cleared. A bare `rescue`
catches every `StandardError`, so a typo'd CDP command or a driver-protocol
change would be indistinguishable from that expected case, and the viewport
override would leak silently into the next example sharing the browser session.

## Real-browser proof (Task 2, 69-06): why the throttle is applied after the setup navigation

`go_slow_link!` began as the file's outermost `before` hook, which meant `sign_in_as_admin`
and the setup `visit "/legislators…"` also ran at 750ms latency and 24 kB/s, against a
`wait: 10`. The profile was later widened "after the drawer-navigation example
intermittently missed the window under a loaded dip container" — but the throttle was
itself a cause of that flake, because it was slowing the fixture work the example depends
on rather than only the navigation under test. Each context now throttles at the end of
its own setup, once the page it navigates *from* is on screen, so the slow link covers
exactly the one navigation being measured.

`slow_link: true` was removed from the describe metadata at the same time. Nothing read
it — `grep -rn slow_link spec/ lib/ scripts/` returned only the tag itself, the helper
definition and the call — so it read like a filter that would exclude these examples from
a run, and no such filter exists.

## Real-browser proof (Task 2, 69-06): why the poll example asserts a poll happened

The poll example asserts that two things stayed false across a poll interval. On its own
that passes for the wrong reason whenever nothing ran at all: if `usePoll` broke, or the
page never hydrated, or the bill never rendered, no placeholder would appear and the
example would still be green. It therefore installs a counter before the watch window and
requires at least one completed request, which turns "no placeholder" into "polls ran and
drew nothing".

The counter has to name a poll rather than count any `inertia:finish`. A bare finish
counter also increments on a `useScoreSubscription` ActionCable-triggered `router.reload`
and on a deferred-prop resolution, so a single one of those satisfied the control while no
poll had run at all. The listener therefore reads `detail.visit.only` and counts only a
partial reload, which is the shape `usePoll(15000, { only: POLLING_PROPS })` sends and the
shape the gate excludes.

The loop also has to run for the interval the example is named after. Exiting the moment
the counter tripped collapsed the observation window to a single `sleep 0.5` sample, at
which point both `eq(false)` assertions passed because almost nothing had been watched.
Both conditions now have to hold before the loop may exit — a full 15-second poll interval
elapsed AND at least one poll completed inside it — and the elapsed time is asserted
alongside the count, so neither can be satisfied alone. The upper bound stays in place so
a genuinely dead poll fails on the assertion rather than hanging.

## Real-browser proof (Task 2, 69-06): why the drawer click dispatches through JavaScript

`click_drawer_link` calls the link's native DOM `.click()` from
`execute_script` rather than Capybara's own `click_link`/`Element#click`.
Capybara's click drives Selenium's W3C actions API — move the pointer to the
element, press, release — and on this suite that path was measurably flaky
against the `[data-testid='page-body-outgoing'][inert]` example specifically
(intermittent "no matches" across repeat runs, never on the other three
examples in the same context, which read `page-body-placeholder` instead).
A parallel debug script that polled `hasAttribute("inert")` directly from
JavaScript, driven by the identical click-and-wait sequence, measured a
consistent 500-650ms window on every run — long enough that Capybara's 5-second
`have_css` wait should never miss it. The one variable between the failing
assertion and the reliable debug script was the click path itself, so the fix
removes the actions-API click rather than the wait.

## Real-browser proof (Task 2, 69-06): why the inert assertion reads one compound selector, not two lookups

An earlier version of the inert-region example read `page-body-placeholder`'s
presence and `page-body-outgoing`'s `inert` attribute as two separate Capybara
lookups, one after the other. On the throttled connection the gap between them
was sometimes wide enough for the navigation to finish in between — the first
lookup would catch the placeholder while it was still up, and the second would
then read `inert` as already cleared, an intermittent failure with no code
defect behind it. A follow-up attempt polled both facts together from Ruby via
`page.evaluate_script` in a hand-rolled loop, which traded that race for a
slower one: each poll tick paid a full WebDriver round trip, and on some runs
that was too coarse to ever observe the window at all, timing out instead.
`have_css("[data-testid='page-body-outgoing'][inert]", wait: 5)` reads both
facts as one compound CSS selector, so Capybara's own polling — already proven
reliable for the placeholder-presence assertions elsewhere in this file —
retries the whole condition as a single unit instead of racing two lookups
against each other.

The two focus examples read `document.activeElement` through `evaluate_script`
at first, which reintroduced the same race one step removed. React writes and
removes `inert` in the commit phase, and `PageBodySlot` moves focus in a passive
effect flushed after it, so a matcher that succeeds on the attribute can still
be running ahead of the focus move — and the reads carried no tolerance, so
both examples could fail in either direction. They now assert the focus fact
itself, through the `:focus` pseudo-class Capybara passes straight to the
browser: `output:focus` on the way in and `[data-testid='page-body-outgoing']:focus`
on the way back. Both pass `visible: :all`, because the announcement region is
`sr-only` and it is focus, not visibility, that these examples are about.
