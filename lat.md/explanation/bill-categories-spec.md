---
lat:
  mode: explanation
---
# The bill categories browser spec

`spec/system/bill_categories_spec.rb` drives the `/bills` category filter and the `/admin/categories` screen in a real browser, pinning behaviour that was first checked by hand.

## What the spec pins

Two surfaces are covered: the reader's category filter on `/bills`, and the operator's category management screen at `/admin/categories`.

On `/bills` the choices offered are the server's list of active categories, printed as stored — "Budget & Taxes" among them, so nothing re-capitalizes or mangles a stored name. A bill survives the filter when it carries at least one of the picked categories, and the picks live in the URL, so a filtered view can be shared and returned to.

On `/admin/categories` the spec walks the lifecycle: adding a category with its live bill count, renaming one — the name alone, never the slug — switching one off and back on, and the "Reactivate it instead." hint a new name matching a switched-off category produces. Each of those takes effect at runtime with no deploy. Switching off a category that is already on a bill drops its choice from `/bills` and keeps the underlying `bill_categories` row.

### Permanent removal follows deactivation

The category resource is plural because it has an index, and permanent deletion is available only after a category has first been switched off.

Deactivation is reversible; destruction is not. The two-step route contract keeps the ordinary category-management path from deleting a category that is still active.

## What it leaves to other tests

Two neighbouring behaviours are deliberately absent, written down so the gap reads as a choice rather than an oversight.

The per-bill category override has its own browser spec in `bill_category_override_spec.rb`, a component test over the summary and positions screen, and request specs for `Bills::CategoriesController`.

The cold-start smoke check and live-model category assignment are infrastructure and paid-model concerns, which sit outside a browser regression spec.

## The round trip re-reads the URL and not the list

The example that leaves a filtered page and returns to its URL re-reads `current_url` alone, and does not assert the filtered bill list again on the way back.

Deferred props do survive a navigate-away-and-return on the server side, which `spec/requests/bills_deferred_reload_spec.rb` covers directly. The other candidate was a version conflict answered with a 409, and that cannot arise here: asset digests stay fixed for the whole suite, so no reload is refused as stale.

On the client, browser history navigation (`popstate`) in `@inertiajs/core` restores cached props directly from decrypted history state without re-requesting if already resolved, or cleanly re-fires `loadDeferredProps` if the prior request was aborted in flight.

The timeout this example used to hit under full parallel load was contention for CPU and threads, together with `wait_until_loaded` waiting for `#nprogress` to be absent before it had appeared ([[capybara-wait-semantics#What wait_until_loaded proves]]). Re-reading `current_url` keeps the contract the example was written for, that the chosen category survives in the address, and leaves the placeholder-to-content transition to be covered where it can be watched directly.

## Rows are re-queried rather than held

Every assertion over a table row goes through `have_css` with the row's text, rather than `find` followed by a read or a click.

`find` hands back one element, and the page's next render replaces it. A click inside the old node reaches something the browser has thrown away, so a dependent input never opens and the next `find` times out — the shape behind the rename example failing once in a full run. Reading from a held row meets the same element-identity problem from the other side and fails as "stale element reference", which is why the deactivate assertions re-query both before and after that flow's reload.

The ordered patterns — `/Housing.*1/`, then `/Housing.*Inactive/` — match the name column ahead of the usage and status columns, and carry no word boundary around the count: the table's cells join with no whitespace ("Housing1Active…"), a shape a word-boundary pattern never matches.

## Presence is established before absence

The example asserting that a switched-off category's choice has gone from `/bills` first asserts that something is present, the bill's title.

"No Housing choice" is equally true of a page that errored, redirected, or stopped drawing the filter at all, and `wait_until_loaded` proves only that the progress bar is gone, which is another absence ([[capybara-wait-semantics#What wait_until_loaded proves]]). The title is the anchor because it arrives in the same delayed payload the filter choices come with.

## The smoke-test fallback for the admin screens

`spec/system/admin_categories_spec.rb` and `spec/system/admin_llm_settings_spec.rb` share a recorded fallback for a Radix Select, an inline rename control or a confirm dialog that cannot be driven in headless Chrome.

The fallback is a smoke test: the page is visited, the heading and the affected row are read, the outcome is checked in the database, and a follow-up issue is filed rather than more time spent forcing the interaction. Both specs currently drive the full round trip, so this is a plan recorded ahead of time rather than a shape either spec has needed.
