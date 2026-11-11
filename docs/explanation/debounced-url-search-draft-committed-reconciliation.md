---
mode: explanation
summary: "Why useDebouncedUrlSearch keeps a per-keystroke draft value reconciled against the committed URL search term during render, instead of in a useEffect."
status: agent-extracted
related: [docs/explanation/pipeline-controls-pending-state-race.md, docs/explanation/editable-summary-field-server-resync-guard.md]
---

# Reconciling a debounced search draft against the URL

`useDebouncedUrlSearch` (`app/frontend/hooks/useDebouncedUrlSearch.ts`)
needs a per-keystroke "draft" value, since the committed `?search=` URL
param only updates once the debounced visit actually lands. `null` means
"no draft — show the committed URL value instead," which is what makes the
browser's back/forward buttons behave correctly once a search has settled.

Reconciling the two happens DURING render, using React 19's documented
"storing information from previous renders" pattern (the same approach
`usePipelineControlsState` uses) instead of a `useEffect`: once the
committed URL value catches up to the draft — the hook's own search visit
echoing back — the draft is dropped. A draft the URL never matches, because
the reader is still mid-typing, stays as-is.

## `IDebouncedUrlSearchConfig` fields

`only` is the list of Inertia props to refresh for the search visit (a
partial reload allowlist).

`resetParams` names URL params that a new search should clear out (e.g.,
a cumulative `?page` window that no longer applies once the search
changes).

## Why the committed search term lives in the URL

This is URL-driven, debounced text search for list pages. The
committed search term lives in the URL (`?search=`, trimmed, and removed
entirely when empty), so a shared link reproduces the same search and the
browser's back/forward buttons restore it correctly. `value` updates on
every keystroke so the input feels responsive, while updating the URL (and
the partial reload that triggers) lags behind by `debounceMs`.

Callers should pass module-level constants for the array config (`only`,
`resetParams`), so the `onChange` callback keeps the same identity across
renders instead of looking like a new function to React every time.

## Why the default debounce is 350ms

`DEFAULT_SEARCH_DEBOUNCE_MS` is a trailing-edge debounce (wait for a pause
in typing, then act) for search-as-you-type. It's set slightly wider than
the pipeline controls' 250ms click-coalescing delay (in
`usePipelineControlsState`), since keystrokes arrive faster than checkbox
clicks.

## Why the pending timer is cleared on unmount

This timer-ref-plus-unmount-cleanup pattern mirrors `usePipelineControlsState`
and `useSearchParams` (cancelling a pending timer on unmount counts as
syncing with an outside system, so a `useEffect` is the right tool here).
Without this cleanup, typing something and then immediately navigating
away would still fire the pending search visit and yank the reader back to
this page.
