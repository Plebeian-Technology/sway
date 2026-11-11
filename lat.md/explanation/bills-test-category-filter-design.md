---
lat:
  mode: explanation
---

# Why Bills.test.tsx is structured this way

`app/frontend/pages/__tests__/Bills.test.tsx` guards two things about the `/bills` page in the current UI.

## OR-intersection, not AND

The category filter must show a bill that has ANY of the chosen categories.

The test cases are built so that breaking that — swapping `.some` for `.every`, or comparing the single `bill.category` field instead of the `categories[]` array — turns the "renders filtered from the URL" tests RED rather than passing by luck.

The fixtures give billA "health" only, billB "housing" only, and billC both — the bill that makes these tests mean something:

- `.some("health")`: true (health is in `[health, housing]`) → it shows
- `.every("health")`: false (housing is not in `[health]`) → it is hidden

So filtering by `["health"]`, `.some` gives 2 bills and `.every` gives 1.

## The filter lives in the URL, not component state

The chosen filter lives in the URL (`?categories=Health,Housing`) rather than in component state, so the browser's back and forward buttons restore it.

The two halves are tested separately: given a URL, the right bills appear; and clicking a chip sends the right URL to `router.get`. Splitting them avoids having to fake Inertia re-rendering the page.

## Test setup notes

`Deferred` from `@inertiajs/react` is replaced with something that renders its children straight away.

`Deferred` from `@inertiajs/react` is replaced with something that renders its children straight away, so the bill cards appear at once instead of waiting for Inertia to say the delayed prop has arrived (which never happens in a unit test). The single `category` field is `"infrastructure"` on every bill — deliberately different from the `categories[]` array — so falling back to `categories.includes(bill.category)` fails here too, the same way it would in production.

## Why categoryFilterHref.ts builds the URL the way it does

The chosen category filter lives in the URL (`?categories=Police,Health`), not in component state, so a shared link opens with the same filter and back/forward restore it.

No category name contains a comma, so a comma safely separates several of them.

`categoryFilterHref` builds the address a change to the category filter navigates to. Selecting nothing must DROP the parameter rather than leave it empty, and every other parameter — page, sort, direction, search — has to survive untouched, or clearing the categories would silently throw the reader back to page one of a different order.
