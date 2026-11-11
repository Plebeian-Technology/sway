---
lat:
  mode: explanation
---

# Bills category filter

The `/bills` category filter is one multi-select control, shared by all four bill-list layouts, whose selection lives in the URL rather than in component state.

It replaces a row of toggle buttons — one chip per active category — copied into each layout's own markup. Twenty categories ship seeded, so the row was the widest thing on the page in every theme, and each copy had to be checked separately for the state a screen reader hears.

## One control, four themes

`CategoryMultiSelect` renders the label, the trigger and the popover once, and each layout hands it two class names: the chrome its sort and search fields already use, and its eyebrow style for the label.

The panel itself is styled from theme tokens alone — `--popover`, `--border-strong`, `--rule-hair`, `--radius`, `--space-unit` — which every theme is required to declare, so a shared stylesheet reads as that theme's own without a per-theme rule. That is the same arrangement `styles/theme-selects.css` uses for the native selects, and it is why three layouts lost their chip rules rather than gaining a multi-select variant each.

The trigger names its own selection: with nothing picked it reads "All categories", and otherwise the picked names in order. A screen reader hears the state from the trigger and from each option's checkbox, so no layout has to carry a toggle's pressed state of its own.

## What the phone shows instead

The Expo app renders the same choice as a trigger reading "Categories" with a count badge, which opens a sheet of checkbox rows. It never prints the picked names.

Twenty seeded categories laid out as a scrolling row of buttons took the full width under the heading and pushed the first bill card off a phone screen, which is the shape the trigger replaced. A count fits the narrower trigger where a joined list of names does not.

The sheet carries the same search box, the same checkbox rows and the same "Clear all" as the popover, all from `PARITY_COPY.bills`, so the trigger's summary is the only divergence, recorded as `[platform]` in the web/mobile parity diff. Without an `onClear` handler the sheet clears by calling `onToggle` once per selected category.

`titleize` is copied into the mobile component rather than imported from `sway_utils`, because that module can pull in browser-only APIs. It changes a row's display text alone; the filter still compares raw category values.

## Why the selection stays in the URL

The picked categories are read out of `?categories=Police,Health` on every render and written back through `categoryFilterHref`, so a shared link opens filtered, and back and forward restore what the reader had.

Toggling one asks Inertia for `all_categories` alone with `preserveState`, so the popover stays open across the round trip and several categories can be picked in one visit to the control. No category name contains a comma, so a comma safely separates several of them.

Clearing drops the parameter rather than leaving it empty, and every other parameter — page, sort, direction, search — survives untouched, or clearing the categories would throw the reader back to page one of a different order.

### How much of the list is shown lives in the URL too

`?page=N` names how many pages are shown together, not which single page, so
the whole visible list is reconstructible from the address.

Load more asks the server for the bill list and the total alone, and the server
returns the whole list each time, so nothing in the browser stitches pages
together or weeds out duplicates. Writing the new number into the URL is what
lets the view be shared and restored by back and forward, the same property the
category picks have.

Load more, sort and search all refresh the same pair of props together, so the
visible bills and the total can never disagree. That list is declared at module
level rather than inside the component, so the callbacks reading it are not
rebuilt on every render.

Where a control sits relative to `<Deferred>` decides what its test has to
stub: the load-more control renders only once the deferred bills prop has
resolved, while the search input and the sort select sit outside it and render
before that.

### The bill count is drawn inside the deferred boundary

Every list layout renders its "N bills" count inside `<Deferred>` rather than
above it.

Outside it the count reads zero while the bills prop is still resolving, so
"No bills found" flashes on screen before the list arrives — an empty state
asserted about data that has not been fetched. Inside the boundary only the
loading fallback shows until there is a real answer to give.

The fallback renders accessible loading copy alongside structured card skeleton
blocks matching each theme's list geometry (`.placeholder-block` in
`.bnl-grid > .bnl-card`, `.ball-contests > .ball-contest`,
`.csl-board > .csl-poster`, or `.space-y-4`). This preserves vertical layout
space and prevents layout collapse and cumulative shift while the deferred prop
resolves. Controls rendered outside the deferred boundary remain interactive
throughout the handoff, and keyboard focus is preserved across the resolution
transition.

## The single-subject category column is retired

`category` was the one-subject field the bill form used before the topic list replaced it, and the column now defaults to an empty string.

A bill created without one therefore has to be creatable: the form no longer
sends the field at all, so treating its absence as a validation failure would
refuse every bill an admin creates. What a bill is about is the list of
categories attached to it, and that list is what every reader consults.

## Why a bill matches on ANY category

A bill shows when it carries any of the picked categories, not all of them: picking more categories widens the list, which is what a reader picking a second topic means by it.

The filtering happens in the browser over the bills the server already sent, so it must never be confused with paging — "load more" compares the raw count the server sent against the server's total, not the length of the filtered list.

A bill the classifier cannot place is stamped with that outcome rather than left unstamped. The backfill selects bills with no categories, so an unstamped no-match re-enters the set on every boot and buys the same refusal again; recording the deterministic no-match is what ends the loop.

## Why the layout sweep survives the shared control

`categoryFilterState.test.tsx` still renders the filter once per registered layout, even though all four now mount the same component, because what it checks is the wiring rather than the control.

A layout that forgets to pass `selectedCategories`, or passes the toggle where the clear belongs, renders a control that looks right and filters nothing.

The set of layouts is the set of `*BillListLayout.tsx` files in the directory, and the sweep compares that listing against its own table, so a fifth layout added without being added to the table fails there rather than shipping unchecked.
