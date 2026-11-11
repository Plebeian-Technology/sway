---
mode: explanation
summary: "Why useOfflineBannerState resets its banner state during render when isOnline changes, instead of in a useEffect, and what bug that replaced."
status: agent-extracted
related: [docs/explanation/pipeline-controls-pending-state-race.md, docs/explanation/debounced-url-search-draft-committed-reconciliation.md]
---

# Why `useOfflineBannerState` resets its state during render

`useOfflineBannerState` (`app/frontend/hooks/useOfflineBannerState.ts`)
adjusts `bannerState` DURING render when `isOnline` changes, using React's
documented "storing information from previous renders" pattern — not a
reset-on-prop-change `useEffect`. An earlier version used a `useEffect`
for this, which produced one stale frame every time `isOnline` changed;
that's exactly the case React's docs warn against handling with an
effect.

A fresh online→offline transition reveals the banner even after a prior
dismiss; going back online resets it to hidden, clearing any
asserted/dismissed memory.
