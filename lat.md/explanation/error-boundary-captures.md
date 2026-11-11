---
lat:
  mode: explanation
---
# How often a page error is reported

The page-level boundary clears a shown error when the address changes, and that reset is arranged so a reader who lands on a second broken page still produces one report per error rather than two.

## One capture per error, however the reader arrives at it

[[app/frontend/components/error_handling/PageErrorBoundary.tsx]] resets through `getDerivedStateFromProps`, which runs before each render, so the reset for a new address is already applied by the time a child of that new page throws.

The order matters because `onRenderError` is not only a report: it clears session storage, local storage and cached pages. Running it twice for one error would run those resets twice as well.

An earlier `componentDidUpdate` form reset after the commit instead. Arriving on a broken page from a healthy one, the address change and the throw landed in the same commit: the throw was caught and reported, then the update saw a changed address with an error set, cleared it, re-rendered the same child, and the same error was caught and reported a second time. This is the case react-error-boundary guards by not checking its reset keys on the first update after an error is set.

Two paths are pinned by `app/frontend/__tests__/PageErrorBoundary.test.tsx`: a healthy page followed by a throwing one reports once, and a throwing page followed by a different throwing one reports twice — two errors, two reports, which is correct rather than doubled.
