---
lat:
  mode: explanation
---
# Reading the activity log

The Bill Creator's activity log is paged ten entries at a time over a buffer the client holds, extended fifty at a time from the server's forward-only cursor. [[app/frontend/components/admin/creator/activity-log/useActivityLogStream.ts#useActivityLogStream]] owns that buffer; [[app/frontend/components/admin/creator/activity-log/useHighlightPulse.ts#useHighlightPulse]] scrolls a `?highlight=` row into view once.

## What the hook owns

The hook owns a buffer of every entry fetched so far, a page number into that buffer, and a queue of entries pushed over the WebSocket that have not been shown yet.

The buffer only ever grows or gets replaced wholesale (a filter change resets it to page one); it is never spliced into from a live push, which is what makes backward paging free — every earlier page's content is still sitting in the buffer, so moving back is a plain slice with no request. `PipelineActivityLogEntry`'s cursor stays exactly as `BillCreator::ActivityLogPage` built it — forward-only, fifty entries per fetch — because `spec/requests/admin/bills_pipeline_llm_activity_log_spec.rb` pins that exact contract (tests A and B) and sits outside this hook's edit scope. Reworking the cursor to a bidirectional or offset scheme, or shrinking the fetch to ten, would need changes to that spec too. Paging ten at a time client-side over what the existing fifty-per-fetch cursor already returns avoids touching it at all, at the cost of a numbered page only being reachable once its batch has been fetched — `goToPage` clamps to the known page count rather than fetching ahead, and a distinct "Load older entries" control (visible only on the last known page while more exists) is what pulls in the next fifty-entry batch.

## Live entries never auto-insert into the buffer

An entry arriving over `subscribeActivityLog` carries the same risk on page one as on page three: splicing it into the buffer shifts every later entry's position.

That would change a page the operator is currently reading, with no action of their own — on that page or any other.

`onAppend` never touches the buffer. It queues the entry (deduped against both the buffer and the queue) and the panel shows a count with a "Show N new" control; only clicking that control merges the queue into the buffer and jumps to page one. This holds regardless of which page is open, including page one — showing entries only ever happens as a result of an explicit click, never as a side effect of one arriving.

### The queue is discarded, not preserved, across a filter change

An entry that arrives while a filter change is in flight is dropped when that change's own response lands, rather than carried into the new filter's queue.

The old forward-only-append design went the other way, keeping a mid-reload broadcast and splicing it in once the request settled, because there the broadcast WAS the list's only record of that entry. Here `subscribeActivityLog` has already raised a toast for it (`activityLogChannel.ts`, unconditionally, before `onAppend` even runs) regardless of what the queue does, and the entry may not even match the filter that just landed — keeping it queued past a reset would show something the new filter never fetched. The server's fresh response is treated as the authority on what belongs under the new filter.

## Where a load-more lands, and why it is not the next page

After a fetch the hook jumps to the page holding the first entry of the new batch, worked out from how long the buffer was before the merge rather than by adding one to the page just read.

The two are the same only while the buffer is a whole number of pages long, which is true of a buffer built purely by fetching: the server's batches are fifty and a page is ten. Showing queued live entries breaks it. Those arrive in whatever number the run produced, prepend to the buffer, and leave its length at nothing in particular — so on a fifty-three entry buffer, adding one to the page just read skips seven of the fifty entries just fetched, and they are only reachable by paging backwards to look for them. Counting from the buffer's own length lands on the page where the new content genuinely starts, whatever the length happens to be.

## The page number is clamped where it is read

The page a caller asked for is held as it was asked for, and every read of it is clamped to the page count the current buffer supports.

Clamping on the way in cannot hold on its own: the buffer changes under a page number already stored, and a fetch that returns only entries already held leaves the count where it was while the landing page above points one past it. Clamping at the point of use makes an out-of-range page unrepresentable in what the panel renders, rather than something each writer has to remember not to produce.

## Why the reset effect skips once for a load-more fetch

`extendingRef` is true while a load-older-batch request is running, so the effect that resets the buffer from the server's props skips exactly once.

That request's own `onSuccess` appends the new batch instead, rather than the effect wiping the buffer down to just that batch and losing every earlier page.

The fetch changes the same `activity_log_entries` prop a filter change does, and Inertia renders the new props before calling `onSuccess`, so the reset effect runs first; the flag is what tells it this particular prop change should extend rather than replace. It is cleared again in the fetch's own `onFinish`, not only on success, because a failed request calls `onFinish` without ever changing the props — left on, that flag would wrongly skip the next real reset (a filter change).

## Why a load-more waits for a filter change

Both controls send through Inertia's single-slot request stream, so starting one cancels the other. A load-more clicked before a filter change came back therefore has to be held rather than sent.

Sending it cancelled the filter change and lost it silently, and the load-more then rebuilt its own parameters from the address, which still held the old filter because the cancelled visit never got to update it. Older entries under the filter the operator had just left were appended to the list, while the dropdown on screen showed the new one.

Re-applying the dropdown state to the load-more request was the alternative, and it fixes only half of it: the cursor the click was made on counts against the old filter's result set, and the buffer it would extend is the old filter's entries, so the list ends up holding two filters at once.

`filterVisitsInFlightRef` counts the filter changes that have gone out and not yet reached `onFinish`, and a click made while that count is above zero sets `queuedLoadMoreRef` instead of sending anything. It counts rather than flags because one filter change can supersede another: a boolean cleared by the first visit's `onFinish` would report the second as settled while it was still running, and the next click would go out against a list about to be replaced.

That filter change's own `onSuccess` fires the held click, taking the cursor from the props that just landed and the filters from the visit's own data rather than from the address, for the same reason `onFilterChange` does. Inertia renders the new props before calling `onSuccess`, so the reset effect has already replaced the buffer by then and the fetch extends the new filter's first page.

A filter change the server rejects releases the click too, from `onError`. Nothing replaced the list in that case, so the fetch is served from the cursor the click was made against and the filters still in the address — the entries that remain. Without that release the click was dropped silently, since `onSuccess` is the only other thing that consumes the queue.

## Why the URL param list includes the cursor

The query parameters the hook owns are the three filters `ActivityLogPanel` reads back out of the address, plus the cursor a load-more fetch sends.

A filter change starts over from the top, and a cursor counted against the previous filter means nothing against the new one — the load-more fetch below leaves one in the address for the next filter click to find, so stripping it before that visit keeps a stale cursor from riding along. Everything else in the address belongs to some other control on this page (the panel is mounted beside `RunSelector` on the pipeline tab) and is carried through untouched.

`onFilterChange` builds its request params from its own `current` argument, not by reading the address back out — the visit's data carries the new filter set, and an old value left in the address that the new data does not name would otherwise survive an Inertia merge.

## Listen on two channels

`useActivityLogStream` subscribes to both the current run's channel and the "global" one, and unsubscribes from both on cleanup — the double unsubscribe is what makes React StrictMode's double mount-and-unmount safe here.

## Why the highlight param is removed after use

The one-shot `?highlight=ID` parameter directs attention to a freshly created activity-log row once on arrival, and subsequent clearance prevents repeated flashes on refresh.

The id this points at is normally the entry a same-visit flash just created, which lands on page one of the freshly reset buffer; an id from further back in the log will not resolve to a mounted row (only the current page renders), and the hook already no-ops gracefully when the element is absent.

When the hook mounts, [[app/frontend/components/admin/creator/activity-log/useHighlightPulse.ts#useHighlightPulse]] updates history state using [[app/frontend/sway_utils/queryParamClearedSignal.ts#setQueryParamCleared]] rather than deleting the parameter outright. In a query-parameter navigation carry environment, a bare deletion appears as an omission rather than deliberate removal, which would cause an interceptor to resurrect the highlight parameter from previous navigation state. Emitting `?highlight=` explicitly signals intentional clearance across transport boundaries, ensuring downstream navigations suppress and strip the parameter rather than carrying it forward.

Deterministic clearance coordinates with Inertia's navigation lifecycle. Inertia's client-side runtime manages history updates through an asynchronous queue. Under test worker load, delayed resolution can cause Inertia's history replacement to fire after a fixed mount timeout, restoring the server-rendered `?highlight=ID` query string. Registering lifecycle listeners (`router.on("navigate")`, `router.on("finish")`) with Inertia's router ensures that any subsequent navigation or history reconciliation immediately re-asserts the cleared state.

Mounting of the hook depends on application-origin storage isolation. The activity log renders inside [[app/frontend/components/CollapsiblePanel.tsx#CollapsiblePanel]] backed by local storage key `sway:pipeline-llm:accordion:activity-log`. If previous browser sessions leave a collapsed state (`0`) in storage, the panel unmounts [[app/frontend/components/admin/creator/ActivityLogPanel.tsx#ActivityLogPanel]] and suppresses hook execution. Browser test suites avoid this by purging local storage on the application origin rather than on opaque origins like `about:blank`, where browser security restrictions silently prevent storage manipulation.

## Memoized rows and default-omitting filter URLs

`ActivityLogEntryRow` is wrapped in `memo` because `ActivityLogPanel` re-renders the list on every WebSocket message and filter reload while individual entry objects remain referentially stable.

`buildFilterParams` layers requested filter overrides onto the active filter state and omits any key that matches its default (`all_bills`, `all`, `7d`) so the query string stays compact.

## Why relativeTime clamps future timestamps to just now

[[app/frontend/sway_utils/datetimes.ts#relativeTime]] returns `"just now"` whenever the computed elapsed seconds are negative.

When the server clock or a development container clock runs slightly ahead of the browser clock, a newly created timestamp sits in the future relative to `Date.now()`. Clamping negative deltas prevents the UI from rendering strings like `"-1s ago"`.
