---
lat:
  mode: explanation
---

# Dependency build scripts

A package can run arbitrary code on install. pnpm refuses that by default here, and every package that wants to is named in `allowBuilds` with a deliberate `true` or `false`.

That map is a record of decisions, not a cache. Each entry was answered once by a person, and the answer survives in the file so the next reader inherits the reasoning rather than the outcome alone.

## Why a pending entry is not a harmless one

An unanswered entry does not sit quietly until somebody has time for it.

While pnpm holds ignored builds, every `pnpm run` and `pnpm exec` in the checkout exits 1 — not only the commands that touch the new package. Adding promptfoo leaves four builds pending, and `pnpm fmt:check`, `pnpm lint` and the pre-commit hook, which shells through pnpm, all then fail for unrelated work in the same tree. In a checkout shared with another process that reads as someone else's change breaking the build.

A `false` is therefore a complete answer that restores the tree, not a deferral of one. The two real states are approved and declined; pending is an outage.

## Why the eval harness declines all four of its

promptfoo arrives with four: `@playwright/browser-chromium`, `@swc/core`, `onnxruntime-node` and `protobufjs`. None is reachable from the way this repo uses it.

The providers are HTTP — a local llama.cpp server, and OpenRouter once that provider lands — so the browser provider never loads. Judging left promptfoo entirely, so the embedding-backed assertions that `onnxruntime-node` serves have no caller. The custom providers and prompt functions are plain `.mjs`, so nothing asks `@swc/core` to transpile TypeScript. `protobufjs` arrives underneath the others.

Approving them anyway would not be free. `@playwright/browser-chromium` fetches a browser of roughly 150MB on every fresh install, CI included, to support a provider no configuration here names. promptfoo runs with all four declined.

The narrow shape is what makes this safe to revisit rather than permanent. If a later phase reaches for one, that single package can be approved then, against evidence of what needs it — which is how the six standing `true` entries were each added.
