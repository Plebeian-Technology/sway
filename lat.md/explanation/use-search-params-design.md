---
lat:
  mode: explanation
---

# Why useSearchParams is built the way it is

Design rationale for useSearchParams: why it re-reads the query string every render and the debounce/cleanup pattern its add/remove navigation uses.

## INavOptions fields

`only` names the page props to re-fetch.

When set, the server sends back only these props instead of the whole page — the standard way to do search-with-filters. Leave it out and the whole page reloads, the way the older code did it.

`debounceMs` controls how long to wait before navigating, in milliseconds. Above 0, every call made inside that window collapses into a single request. Use it for things that fire constantly, like search-as-you-type.

## Why the query string is re-read on every render

Re-reading the query string costs one pass over it, which is cheap enough to redo on every render — and it keeps these values from going stale after Inertia navigates to a new URL.

## Why the debounce timer is cleared on unmount

`add` and `remove` with a debounce set a timer that calls `router.get` later; without cleanup on unmount, a component that disappears mid-wait would still send the visit.

`usePipelineControlsState` cleans up the same way. Clearing a timer on unmount is syncing with something outside React, which is one of the few things an effect is meant for.
