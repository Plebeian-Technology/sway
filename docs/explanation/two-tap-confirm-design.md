---
mode: explanation
summary: "Why useTwoTapConfirm exists as a shared hook (extracted from PipelineProgress.tsx) and why it never performs the confirmed action itself."
status: agent-extracted
related: []
---

# Why `useTwoTapConfirm` is a shared hook

"Tap once to arm it, tap again to confirm" — and it disarms itself after
a few seconds if nothing happens.

The logic came out of `PipelineProgress.tsx`, which already had a
two-tap cancel button. `PipelineProgress` and `RunConflictBanner` both
use this hook, so the 3-second window is decided in one place.

Actually doing the thing (calling `router.delete`, say) is up to the
caller. That keeps this hook from knowing about any particular route.
