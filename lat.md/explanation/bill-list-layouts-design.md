---
lat:
  mode: explanation
---

# Bill-list layout components (app/frontend/components/bill/list-layouts/)

Why the ballot, chamber, cornerstore, monochrome, service manual, Swiss grid, and default bill-list layouts carry their visual identities.

## BallotBillListLayout.tsx

Ballot-style bill list: shows bills like the contests printed down a voting ballot — a header carrying the jurisdiction, then one ruled contest per bill. No cards, no shadows, matching `ballot-bill-layout.css`.

The bill's identifier, its chamber, and the category filters are three different kinds of information, so they should not all look like the same pill-shaped label. Here the bill number is a boxed code (this contest's identifier), the chamber is plain text next to it, and the category filters are the only clickable chips — so the shape of each piece shows whether it's fixed information or something you can interact with.

## ChamberBillListLayout.tsx

Chamber-style bill list: shows bills like a printed legislative agenda read by lamplight.

Chamber-style bill list: shows bills like a printed legislative agenda read by lamplight — a plaque with a brass-colored ruled line holds the session and category filters, and each bill is listed like an agenda item with a brass section mark, a caption set in the Fraunces serif font, and a glowing bar showing how much support it has. Reuses the same dark, formal-agenda look as the chamber bill-detail page.

## CornerstoreBillListLayout.tsx

Corner-store-style bill list: shows bills like a bulletin board in a shop window — a masthead, then one screen-printed-looking poster per bill. Uses the same flat, hard-edged, offset-shadow look as `cornerstore-list-layout.css`.

The bill number looks like a poster's stencilled code, the chamber is plain text underneath it, and the category filters are the only clickable chips. Three different kinds of information get three different visual shapes.

## DefaultBillListLayout.tsx

Core responsive layout organizing bill grid items, filter drawers, search bars, and pagination controls across viewports.

### The one-row control layout

One row of controls instead of three stacked full-width fields (sort and search stay URL-driven — see [[docs/reference/url-driven-list-controls.md|URL-driven list controls]]).

Locale gets the widest, most flexible column, because jurisdiction names like "Baltimore, Maryland, United States" are the longest text in the row — cutting one off mid-word would look like a bug. On small screens, locale still gets the full width for the same reason, while sort and search share the second row.

### The category filter list

The row of boxed category buttons is a plain text list: an underline marks which filter is active, and the buttons drop their box styling entirely (bill cards elsewhere still keep their pill-shaped badges).

Buttons show each category's exact text so the system test, which looks for those exact button labels, keeps working. On small screens the list becomes a single-line horizontal scrolling strip — the same pattern the mobile app's `CategoryChipStrip` component uses — instead of wrapping into many lines; on medium screens and up it wraps in place instead.

`py-1` adds tap-target padding without shifting the text baseline that the label aligns to; `shrink-0` and `whitespace-nowrap` keep each button from breaking apart inside the small-screen horizontal strip.

## BillsSearchInput.tsx

The shared search box for bills lists: one shared placeholder text and test id across all three list layouts, while each layout supplies its own visual style through `className` (neo / bnl-select / cbl-select).

Using `type="search"` gives the browser's built-in "clear" button for free. The page that renders this component handles debouncing (waiting for typing to pause before acting, via `useDebouncedUrlSearch`) — `onChange` fires on every keystroke with the raw text typed so far.

## MonochromeBillListLayout.tsx

Monochrome bill list presents legislation as an editorial proof sheet with a strict single-column measure.

A sixty-five-character reading measure and pure black, white, and gray rules prioritize linear reading and scannability. Bill identifiers appear as IBM Plex Mono codes, and vote sentiment displays as high-contrast tabular tally figures.

## ServiceManualBillListLayout.tsx

Service Manual bill list presents legislation as an authoritative civic directory following public digital service guidelines.

A bold civic accent rule and a structured surface filter well organize legislative discovery. Bill entries feature high-contrast status tags, distinct typography, and plain-language summary previews.

## SwissGridBillListLayout.tsx

Swiss Grid bill list presents legislation as a municipal gazette ledger framed by an exposed hairline grid.

An asymmetric two-column structure places index numbers and legislative codes in a 180-pixel left column. Content cells align jurisdiction details, filter controls, and bill entries along continuous hairline grid borders.

## Featured release dates on Past Bills of the Month

In `"past_bills_of_the_month"` mode, every bill-list layout displays a `<time>` element showing when the bill was featured (`Featured <date>`).

[[app/frontend/sway_utils/datetimes.ts#formatCalendarDay]] formats `scheduled_release_date_utc` through [[app/frontend/sway_utils/datetimes.ts#calendarDayToDate]] so a bare `YYYY-MM-DD` calendar day never shifts to the prior day in Western timezones ([[bill-schedule-calendar-dates#Why local midnight instead of formatting in UTC]]). The timestamp appears as running metadata rather than a clickable chip so its shape reflects non-interactive context, and it is omitted in `"all_bills"` mode.
