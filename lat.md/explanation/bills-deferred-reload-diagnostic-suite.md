---
lat:
  mode: explanation
---

# The deferred bills reload diagnostic suite

`spec/requests/bills_deferred_reload_spec.rb` is a diagnostic suite.

It narrows down WHERE the deferred `bills` reload stalls. In the bill-categories browser test ("go to a bill detail, then back to a filtered /bills URL"), the page reliably sticks on the `<Deferred data="bills">` placeholder ("Loading bills…") whenever the whole suite is running.

These are request specs: no browser, no Vite, nothing else fighting for CPU. They walk the same server-side sequence the browser walks, including the `inertia_load_deferred_props` partial reload — a `GET request.fullpath` with the `X-Inertia-Partial-Data: bills` header, which is exactly what the `<Deferred>` component sends when it mounts.

## How to read the result

Diagnostic output interpretation guide detailing timing markers, cache hit indications, and partial reload sequence assertions.

- If every example PASSES, the server handles the deferred bills reload
  correctly across the whole go-away-and-come-back sequence with the
  categories param. That points at the browser side — `<Deferred>` re-fire
  timing, Capybara, or the Vite dev server under load — not at the server,
  and the URL-only guard in the browser test is the right call.
- If an example FAILS, the stall reproduces on the server, and the failing
  scenario names the trigger: the categories param, session state left by
  the bill-detail visit, or the partial reload itself.

## Why the nil-locale example fires the reload by hand instead of using inertia_load_deferred_props

`inertia_load_deferred_props` leaves the `X-Inertia-Version` header off, which is flaky because `RailsVite.digest` is read at boot — the header a real browser sends can drift from whatever the helper omits.

Building the request by hand, sending the server's own current asset version, avoids that flakiness while still exercising the deferred `bills` prop with a nil locale — the exact condition where an unguarded `at_large_district` call would have raised.

## The stale-asset-version hypothesis

A 409 means "your assets are out of date, reload the whole page." This is the most likely cause of the stall: if the Vite dev server rebuilds assets between the first `/bills` page load and the `<Deferred>` bills reload.

A 409 means "your assets are out of date, reload the whole page." This is the most likely cause of the stall: if the Vite dev server rebuilds assets between the first `/bills` page load and the `<Deferred>` bills reload — easy to trigger when the full suite is hogging the CPU — the reload's version no longer matches, the server answers 409, and the Inertia client drops the partial reload in favor of a full page navigation. The "Loading bills…" placeholder can hang during that navigation. The server is doing the right thing here; any stall lives in how the client handles the 409.
