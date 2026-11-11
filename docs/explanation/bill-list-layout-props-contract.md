---
mode: explanation
summary: "Why the bills-index 'load more', sort, and search constants in list-layouts/types.ts are shaped and shared the way they are, and what BillListLayoutProps hands every per-theme layout"
status: agent-extracted
related: [docs/explanation/bills-controller-design.md, docs/reference/url-driven-list-controls.md, docs/explanation/locale-flag-not-seal-design.md]
---

# `list-layouts/types.ts`: constants and `BillListLayoutProps`

## `BILLS_LOAD_MORE_LABEL` / `BILLS_LOADING_MORE_LABEL`

Shared "load more" text so all three layouts render, and tests target, the
same control. This is a web-only feature — the mobile app just fetches the
full list instead — so it's deliberately kept out of `PARITY_COPY` (the
text shared between web and mobile to keep their wording consistent). See
`BillsController#index` in [`BillsController`
design](bills-controller-design.md) for the growing-window pagination this
label sits on top of.

## Sort constants

`BILLS_SORT_LABEL` / `BILLS_SORT_OPTIONS`: `value` encodes
`"<column>:<direction>"` and must match the allowed values in
`BillsController#index`. The copy and options live in `PARITY_COPY`, the
shared text used by both web and mobile (mobile's `BillsSortStrip` renders
the same list on its own); the web page sends the selection as `?sort` and
`?direction` URL params. See [URL-driven list
controls](../reference/url-driven-list-controls.md) for `useUrlSort`.

`BILLS_SORT_VALUES`, the list of allowed sort values for `useUrlSort`, is
declared at the module level (not recreated inside a component) so the
hook's `onChange` function stays the same object across renders, instead of
looking like a brand-new function to React every time.

## Search constants

`BILLS_SEARCH_LABEL` / `BILLS_SEARCH_PLACEHOLDER` feed the `?search=`
param that `BillsController#index` uses to run a sanitized SQL LIKE match
against bill titles (`bills_total` is already filtered by this search on
the server). The copy lives in `PARITY_COPY` (mobile filters its own
cached list using the same placeholder text). To be clear about its
limits: this only searches titles, nothing else.

## `BillListLayoutProps`

The shape of data every per-theme bill-list layout receives. The page
(`Bills.tsx`) owns the filter state and data-fetching hooks; a layout just
renders the surrounding UI and the list itself.

`onClearCategories` clears every selected category chip back to the full
list in one click. A layout should only show this control while
`selectedCategories` is non-empty.

`hasMoreBills` is the current page of bills loaded from the server: it compares the raw, unfiltered count of loaded bills against
the server's total bill count.

`sortValue` / `onSortChange` are URL-driven sort — the page
reads and writes the `?sort` and `?direction` URL params; a layout just
renders the shared `BILLS_SORT_OPTIONS` list.

`searchValue` / `onSearchChange` are URL-driven search via the `?search=`
param — the page handles debouncing (waiting for typing to
pause) and reads/writes the URL; `onSearchChange` fires on every keystroke
with the raw text typed.
