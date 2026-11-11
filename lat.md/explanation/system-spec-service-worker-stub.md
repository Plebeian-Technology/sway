---
lat:
  mode: explanation
---

# Why ServiceWorkerStub uses CDP injection

`ServiceWorkerStub` (`spec/support/service_worker_stub.rb`) is a shared stand-in for the browser's real service worker, for system specs that drive push-notification flows.

## Why CDP, not execute_script

The stub goes in through the Chrome DevTools Protocol (CDP) call `Page.addScriptToEvaluateOnNewDocument`, so it is in place *before* any site script runs.

Calling `execute_script` after visiting a page is too late — React's `useEffect` has already run against the real `navigator` by then, so PWA registration code would already have touched the real `navigator.serviceWorker` instead of the stub.

## Why it is shared

It lives in `spec/support/` rather than inside one spec file so `user_notifications_spec` and `notification_delivery_spec` share one copy instead of two that drift apart.

## Why a leftover real service worker is cleared before the stub goes in

`Capybara.reset_sessions!` only clears cookies and localStorage.

`Capybara.reset_sessions!` only clears cookies and localStorage — Chromium's register of service workers survives between examples, so one left over from an earlier `visit "/notifications"` (or anything else that triggers `registerPWA()` in `entrypoints/application.tsx`) would compete with the stub this spec injects on the next page load. `clear_real_service_workers!` uses the CDP call `Storage.clearDataForOrigin` to drop the real service workers and cache storage for the test's origin before the stub goes in. It rescues broadly because CDP may already be gone mid-teardown, or missing entirely on a non-Chromium driver — either is fine to ignore here.

## Why the stub copies exactly these methods, and why the active worker matters

The stub copies the parts real callers touch: `register`, `ready`, and `getRegistration` for the push flow, plus `addEventListener` and `removeEventListener`, which PWA registration code calls right away when it mounts.

Without those do-nothing methods, libraries like `virtual:pwa-register` throw `"navigator.serviceWorker.addEventListener is not a function"`, the React tree falls into the global error boundary on the first render, and unrelated specs that happen to run later in the same Selenium session break too.

`PushNotificationsPanel.registerServiceWorker` specifically waits for an *active* `ServiceWorker` before calling `pushManager.subscribe()`. Without the stub's active handle (`state: "activated"`), the panel times out, never POSTs the subscription, and the UI never flips to "Disable on this device" — failing `notification_delivery_spec` at the `wait_for "Disable on this device"` step.

## Why the stub is explicitly torn down after each example

`Capybara.reset_sessions!` resets cookies and localStorage but does NOT undo `Page.addScriptToEvaluateOnNewDocument`.

`Capybara.reset_sessions!` resets cookies and localStorage but does NOT undo `Page.addScriptToEvaluateOnNewDocument` — a stub injected by one system spec would otherwise carry over into the next example's session, causing intermittent `ErrorBoundary` failures whenever PWA registration calls `navigator.serviceWorker.addEventListener` on a stub meant for a different test. `clear_service_worker_stub!` removes every script this module injected via `Page.removeScriptToEvaluateOnNewDocument`, and an `RSpec.configure` `after(:each, type: :system)` hook runs it automatically.

## The offline helpers

`wait_for_sw!`, `go_offline!`, and `go_online!` exist for the offline system spec.

They wrap Selenium 4's CDP network emulation so a test can switch the network on and off mid-example. `wait_for_sw!` keeps checking until `navigator.serviceWorker.controller` has a value, meaning the service worker is installed, activated, and in charge of the page. It must always be called BEFORE `go_offline!`, so the cache has been filled — the service worker must control the page before the network is cut.

## The slow-link profile

`go_slow_link!` shares the same private `set_network_conditions` helper as `go_offline!`/`go_online!`, widened to take latency and throughput instead of the offline-only zeroes it passed before.

A second path to the same browser network-emulation feature would drift from the first one, so the offline helpers and the slow-link helper go through one place.

There is deliberately no `go_unthrottled!` alongside `go_online!`. One existed briefly with a byte-identical body — both called `set_network_conditions(offline: false)` — which left two public names for one behaviour and no rule for choosing between them. Clearing a throttle and coming back online are the same CDP call, so the name that already had callers is the one that survives.

`SLOW_LINK_LATENCY_MS`, `SLOW_LINK_DOWNLOAD_BYTES_PER_SECOND`, and `SLOW_LINK_UPLOAD_BYTES_PER_SECOND` (750ms, ~192kbps each way — widened from an initial 400ms/~400kbps after the drawer-navigation example in `navigation_placeholder_spec.rb` intermittently missed the window under a loaded dip container) are not a model of any particular real network — a phone on a real slow connection might see very different numbers. They exist so a Capybara example can observe the placeholder-and-inert waiting state on screen for more than a single frame, which is otherwise impossible on a development host fast enough to complete a navigation before the next repaint. `docs/explanation/navigation-placeholder-tracer.md` covers what the waiting state is for; this file only covers how the test makes it observable at all.

The two throughput constants are named for bytes per second because that is the unit CDP's `Network.emulateNetworkConditions` takes, and 24,000 of them is the ~192kbps the paragraph above quotes. They were originally suffixed `_BPS`, which reads as bits per second: an editor "correcting" 24,000 to 192,000 on that reading would have made the link eight times faster and quietly restored the flake the profile was widened to cure. The real slow-link measurement — how long a reader on an actual slow connection is really looking at the placeholder — is an operator pass taken separately, not something this synthetic profile can answer.
