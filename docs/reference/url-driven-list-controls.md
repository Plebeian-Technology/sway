---
mode: reference
summary: "Behavior contract for useDebouncedUrlSearch and useUrlSort, the URL-driven search and sort hooks that used to live inline in Bills.tsx."
status: agent-extracted
related: [docs/explanation/bills-controller-design.md]
---

# URL-driven list controls: `useDebouncedUrlSearch` and `useUrlSort`

See `docs/explanation/bills-controller-design.md`'s "Testing search, sort, and
load-more together" section for the browser-level spec that closes the gap
these hooks' unit tests alone used to leave.

## `useDebouncedUrlSearch`

Holds the URL-driven search behavior that used to live in `Bills.tsx`. It
keeps a draft value that changes on every keystroke, so the input feels
instant. It waits until the typing stops, then makes ONE page visit that
writes `?search=` (trimmed, and removed when the box is empty) and clears
the reset params, such as `?page=`. If the component goes away first, a
waiting visit is cancelled. And on each render it compares the draft against
what the URL says, so browser Back and Forward work.

## `useUrlSort`

`IUrlSortConfig.options` is the `"<column>:<direction>"` values this
control accepts. Keep them in step with the columns the server agrees to
sort by (`BillsController#index`, say). `only` is which page props the
server should send back when the order changes. `resetParams` names query
params that re-ordering makes meaningless, such as a running `?page`
count.

Holds the URL-driven sorting behavior that used to live in `Bills.tsx`.
Reading a sort out of the URL follows the same fall-backs the server uses.
`onChange` writes `?sort` and `?direction`, removes them when the choice is
the default, clears the reset params such as `?page=`, and asks for a
partial reload instead of a whole new page.
