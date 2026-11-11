---
lat:
  mode: explanation
---

# Client caches and identity

Page data can contain a reader's name, address and vote. Browser identity transitions must discard that data before another reader sees a destination page. Static assets remain reusable across accounts.

## The three caches

Page prefetch, service-worker storage and encrypted history have separate lifetimes. Clearing one does not clear the others.

- **Prefetch cache** — Inertia holds page responses in memory for navigation. An identity transition cancels pending prefetches and flushes existing entries.
- **Service-worker storage** — only build assets and lazily loaded admin assets remain cacheable. Dynamic HTML and Inertia responses go to the network; the retired inertia-pages and inertia-navigations stores are deleted during activation.
- **Encrypted page history** — Inertia keeps back-button page copies. Server history-clearing signals invalidate those copies when a browser session is established or ended.

## What the page cache is allowed to hold

Dynamic pages require the network because their shared props depend on the signed-in reader. Offline page reading is deferred until closer to feature completion; cached static assets still reduce downloads on slow connections.

Removing only selected routes would leave other pages exposed: shared identity props accompany every full Inertia response, and HTML navigation responses contain the same data. The worker therefore has no dynamic-page cache strategy or cached-page fallback. The offline banner asks readers to reconnect to load pages or vote; it no longer promises cached content.

The admin-asset runtime strategy rejects responses carrying Cache-Control: no-store or no-cache. Build precaching contains fingerprinted assets, never rendered pages. ApplicationController retains max-age=0, private, must-revalidate for authenticated responses, requiring HTTP-cache revalidation; one-time secrets receive the stronger no-store header.

## Static worker lifecycle

The replacement worker activates promptly and deletes legacy page caches during activation. Static caches survive the migration so an update does not discard useful downloaded assets.

A sign-in preflight asks the controlling worker to confirm its network-only page policy. An older controller triggers an update and a bounded wait for replacement. Failure leaves authentication unsubmitted with retry guidance. Removing cache routes from a new bundle alone cannot protect a tab still controlled by an older worker.

Both worker-registration entrypoints suppress the plugin default reload on controller takeover, preserving unfinished forms. The update toast reloads the page only when the reader selects Reload.

## Bill refresh feedback

Bill pages show vote-pending feedback without cache timestamps or background-cache revalidation indicators. Every newly requested dynamic page comes from the network, so a cached-page freshness label would misrepresent its source.

Pages own polling and subscription hooks; themed layouts only display supplied data. Stable module-level theme components avoid remounting the page when its data changes. Theme rendering tests check that full legal wording remains below the shortened heading; eager test imports keep cold chunk transforms outside each example timeout.

Score subscriptions and 15-second polling remain. Bill detail polling excludes user_vote so a refresh cannot overwrite an optimistic vote; Bill of the Month refreshes its bill, sponsor and user_vote props.

## Push delivery

Push notifications remain independent of dynamic-page caching. Payload parsing and destination checks prevent malformed messages from aborting delivery or opening another origin.

Malformed payloads fall back to a notification containing their raw text. Valid payloads carry their destination through notification data. A click reuses any same-origin window and navigates it to the safe destination, including an uncontrolled tab; a new window opens only when none is available.

## Identity changes wait for network-only pages

Phone-first passkeys, discoverable passkeys and passkey registration share a preflight after obtaining a credential. Credential verification is submitted only after the controlling worker confirms that dynamic pages cannot come from its cache.

The preflight cancels Inertia requests, flushes prefetched responses, clears encrypted history and empties web storage before submitting the credential. Immediately before the destination renders, it cancels asynchronous requests and clears those stores again, discarding prefetches started while verification was in flight. A cancelled passkey prompt never reaches this boundary. A failed worker update leaves the submission unstarted and offers a reload-and-retry message.

Successful server sign-in sets Inertia's pending history-clear flag centrally, so its redirect destination invalidates old page history. Refresh-token session recovery sets the same flag. Clearing history only in a client success callback would be too late: Inertia renders the destination before that callback.

## Why last-seen state moved off the cookie

What an admin has already seen of a bill is stored on the server rather than in
a cookie per bill.

A cookie per bill grows without bound as an operator visits more of them, and
the browser's own limit on total cookie size for a site is around four
kilobytes. The failure that arrangement heads towards is not a slow page but a
dropped cookie, and which one gets dropped is not the application's to choose.

### The refresh notice compares one vote timestamp

The Bill Creator's admin refresh notice reports the latest non-manual vote update only when it is newer than that admin's saved view timestamp.

[[app/controllers/bills_controller.rb#BillsController#legislator_votes_refresh_toast_for]] selects the source from a vote at that same timestamp and formats the time in the bill locale, falling back to Eastern time when the locale has no zone. It builds the payload before saving the view timestamp, so a failed source lookup cannot hide a refresh the admin has not seen. Existing views are saved only when a notice is present, avoiding an idle write against SQLite's single-writer database.

## The reload-reason record has to survive its own failures

The development record of why a page reloaded is read only after that reload
has already happened, so there is no second chance to collect the answer.

If the store throws, or hands back something other than what it stored, the
reload is simply unexplained — and an unexplained reload is the thing the
record exists to prevent. Its examples are therefore mostly about it refusing
to fail rather than about what it returns when everything works.

## Why sign-out does not clear them by itself

A server redirect cannot empty browser storage. The web sign-out control still purges the worker caches and unregisters the worker before requesting logout, then flushes Inertia and web storage when the request settles.

The sign-out redirect clears encrypted page history. Account deletion supplies the same history signal; the current deletion caller is the native app, which owns its own client state. Static assets can be downloaded and cached again after a worker purge.

## The rule this generalises

The project has shipped this defect once already, when three per-user locale props were marked as Inertia once-props and one reader's jurisdiction list stayed on screen for the next person.

A cache with no identity in its key is safe only for values that are identical for every viewer. Anything derived from the session — the user, their locale, their admin role, their own vote on a bill — either stays out of the cache or is merged in after the cached part is read.

## Browser upgrade regression

A Chromium regression proves the retired worker can expose a previous reader's cached response, then verifies the compiled replacement removes that route even on a slow or unavailable network.

The fixture switches account cookies with the HTTP cache disabled, so the old response proves service-worker reuse. It replaces the fixture worker with the compiled production bytes, checks cache eviction and the policy acknowledgement, then checks the second reader's response with network latency. Offline dynamic requests fail while a precached script remains readable. The isolated fixture preserves relative precache paths and restores browser networking and storage afterward.

The replacement fixture has a distinct modification timestamp because Rack serves conditional files using second-resolution modification times. The test waits for activated state: automatic takeover can emit controllerchange before activation cleanup finishes.

## Offline interaction regression

Loaded bill pages remain visible when connectivity is lost, but new pages and votes require a connection. Three Chromium examples check this interaction without waiting for a service worker.

The offline spec uses native browser network controls to check honest banner
copy, dismiss the banner and attempt a confirmed vote, and reconnect. The vote
attempt raises the offline alert and reasserts the banner without creating a
UserVote. The voting fixture has a completed account, address, and legislator
in the bill's locale, so a missing vote button is a failure rather than a skip.
Banner selectors use data-testid because the output element's implicit status
role is not a role attribute. Reconnection hides the banner after reachability
recovers. Network state is restored and the browser driver is closed between
examples to prevent offline emulation from leaking into later tests.

These examples do not reload an offline page or require worker activation.
The separate [[client-caches-and-identity#Browser upgrade regression]] covers
legacy cache removal and actual compiled-worker refusal of offline page fetches.
