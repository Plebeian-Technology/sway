---
lat:
  mode: explanation
---

# Offline telemetry

Four events name the moments worth knowing about when the app is used offline. Nothing transmits them: `trackOfflineEvent` writes to the development console and returns.

## Why offline events never leave the browser

The helper shipped in April 2026 with a three-way sink chain, ending in two posts to `/offline_events`. That was never a Rails route, and the 404 was accepted on purpose so measuring the app could not break it.

The chain tried `window.newrelic.addPageAction` first, then `navigator.sendBeacon`, then `fetch` with `keepalive`.

What made the chain hollow is that its first step never existed. New Relic's *browser* agent was never installed: no npm package, no injected timing header, and `content_security_policy.rb` lists neither `js-agent.newrelic.com` under `script_src` nor `bam.nr-data.net` under `connect_src`. Only `newrelic_rpm`, the server agent, is present, and it puts nothing on `window`. Every event therefore fell through to a beacon that 404ed — including sampled cache hits, which the service worker posted to every open window, so the cost was a steady trickle of unroutable POSTs from every visitor to a single-machine deployment.

The sinks were removed rather than given a destination. Nothing consumed the data, and the alternative — a public unauthenticated write endpoint — is abuse surface that a one-Pi deployment would have to rate-limit before it could be safe.

The event vocabulary and the four call sites stay. They record which moments are worth measuring, and they give a future sink one place to be added instead of four. `offlineTelemetry.test.ts` supplies both `sendBeacon` and `fetch` and asserts neither is called, so a sink added without a destination reddens rather than reaching production as a 404.

One event did not stay. `cache_hit` was removed, and with it the service worker's 5% sampling, the lookup of every open window, the postMessage to each, and the dynamic import that answered it. It was the only event no person's action produced, so it fired continuously in production to reach a console line that only development prints. The remaining four each mark something a reader did, and cost nothing until one happens.
