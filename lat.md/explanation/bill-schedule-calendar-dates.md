---
lat:
  mode: explanation
---

# Bare release dates in the bill schedule tab

`scheduled_release_date_utc` is a plain date column: a bare `"2026-09-08"`
with no time in it. The schedule tab turns that string into a `Date` at local
midnight, not UTC midnight, so it agrees with the calendar's own day cells.

## Scheduler navigation, today control, and pagination

Scheduler navigation prioritizes the URL-selected day, provides a non-mutating Today control, and paginates Past scheduled bills in groups of five.

A valid date query parameter takes selection precedence over the bill's stored release date. Date query parameter validation strictly enforces roundtrip calendar formatting (`dateToCalendarDay(parsed) === raw`), ensuring that JavaScript `Date` constructor overflow (such as `2026-99-99` or `2026-02-31`) fails validation and gracefully falls back to the bill's stored release date. The visible month and year synchronize to the active selection across preserved-state navigation, while any stored release date retains its separate scheduled marker. Existing bare local-day parsing and remove-before-reschedule behavior remain intact.

Scheduling and removing a stored release date retain the URL-selected day through [[query-parameter-navigation-carry#Query parameter navigation carry#Centralized interception mechanism#Server redirect carry follows real form writes]]. Removing the release changes persistence without clearing that selection, so [[app/frontend/components/admin/creator/bill-schedule/BillScheduleSelectedBill.tsx#BillScheduleSelectedBill]] keeps Schedule bill enabled for the selected day. [[app/controllers/bill_of_the_month_schedule_controller.rb#BillOfTheMonthScheduleController#update]] owns the monthly write and its success notice. [[spec/system/admin_bill_creator_spec.rb]] waits for that notice before checking the persisted selected day, then verifies the kept address date and the nil release after removal.

The Today button navigates the calendar to the current local month and year in either Month or Agenda view. It operates strictly on local display state, retaining the selected bill and picked date without triggering network requests or schedule writes. Returning to the selected month preserves its highlight.

The Today button's accessible name matches its visible label, allowing assistive technology to target the same control name the operator sees.

Past scheduled bills use independent five-item pagination, preserving the chronological ordering and the full-list total count badge. Its page state is separate from Unscheduled pagination, ensuring navigation in one list does not disturb the other.

## Why local midnight instead of formatting in UTC

`new Date("2026-09-08")` parses a date-only string as UTC midnight per
ECMA-262. Read back with local getters anywhere west of UTC — Baltimore's own
Eastern zone included — that instant falls on the day before.

[[app/frontend/sway_utils/termWindow.ts#formatDay]] hits the same defect for
legislator term dates and fixes it by formatting in UTC.

Formatting in UTC is enough when a value only ever becomes a display string.
The bill schedule tab instead turns the stored day into a real `Date` that
gets compared, with local getters, against the calendar grid's own day
cells — each built as `new Date(year, month, day)`, i.e. local midnight
(`BillScheduleCalendar.tsx`'s `isSameDay` and its `toDateString()`-keyed day
map). Parsing the stored value as UTC midnight while the grid's cells sit at
local midnight would put the two on different clocks, and any comparison
between them would be off by the reader's UTC offset — the calendar would
highlight, or mark as scheduled, the day before the one clicked. Building the
stored value at local midnight too keeps every `Date` in the component tree
on the same clock, so the existing local-getter comparisons keep working
unchanged.

The calendar also marks every day before today as past ahead of looking at
what is scheduled, so the examples that prove this parsing with the fixed day
`2026-09-08` — the Eastern-time examples in `BillSchedule.test.tsx` and
`BillScheduleSidebar.test.tsx` — freeze the clock at a moment no later than
that day. On the real clock the cell reads as past from the following day
onward, and the assertion that it is scheduled fails. The two
picking-a-day examples in the same file click the 15th of the current month
and freeze the clock at the first of a month for the same reason: on the
real clock that cell is past from the 16th onward.

## Why a picked day travels as a bare day

Everything the schedule tab sends about a chosen day — the `date` query parameter and the value written to `scheduled_release_date_utc` — is a bare `"2026-09-08"`, built from the local `Date`'s own year, month and day by `dateToCalendarDay`.

The three used to travel as `Date.toISOString()`, a real instant. Rails casts that into the date column by reading the literal year, month and day out of the string and ignoring the offset, so the result depended on which side of UTC the operator sat. Local midnight on 8 September in Eastern time is `2026-09-08T04:00:00.000Z`, whose literal day is still the eighth; in Tokyo the same click is `2026-09-07T15:00:00.000Z`, whose literal day is the seventh, and the bill would have been scheduled a day early.

It was latent rather than live — every Sway locale is Baltimore City, Maryland or US Congress, so every operator is currently in Eastern time — and it would have surfaced the first time the platform was administered from another continent.

Correcting the offset was the alternative, and it was rejected for the reason above: the column names a day and nothing more, so any instant sent for it has to be converted somewhere, and every conversion is another chance to lose a day. Sending the day the operator actually clicked leaves nothing to convert.

`calendarDayToDate` reads all of them back, so the query string and the stored column now go through the same pair of functions in both directions.

## Why picking a day reaches no server

Clicking a day on the calendar puts that day in the address, and that is the whole of its work.

No controller action reads the `date` query parameter — `bills#new` and `bills#edit`, the two actions behind this page, never mention it — so no prop depends on it. The address carries the choice through a reload, and can be shared.

The click used to travel as `router.get(..., { only: [] })`, which is worse than it looks. Inertia decides a visit is partial by asking whether the `only` array has entries, so an empty one is not a partial at all: no `X-Inertia-Partial-Data` header goes out and the server builds and returns every prop the page has. The visit that was meant to be the cheapest one on the page was the most expensive.

`window.history.replaceState` does the address rewrite with no request. `useSearchParams` re-reads `window.location.search` on every render rather than holding it in state, so nothing observes that rewrite on its own; a reducer bumped alongside it is what makes React read the address again. The same shape is used for the Notifications page's tab, described in [[notifications-tab-url]].

## How scheduling adapts to phone browser viewports

Phone browser viewports require dedicated sizing and presentation to ensure scheduling controls remain touchable and legible without horizontal page overflow.

A 7-column calendar grid squeezed onto a 390px or 320px screen leaves day cells too narrow for standard finger taps unless card padding is compressed. Using `p-2 sm:p-4` alongside `h-11 sm:h-10 min-h-11 sm:min-h-10` guarantees that day cells clear the 44px by 44px touch target minimum at 390px. Wrapping the month grid in an overflow container prevents horizontal page blowout down to 320px.

Because Radix tooltips do not open on mobile touch devices, phone users cannot discover what bill is scheduled on a colored date cell without navigating away. An integrated Agenda view toggle presents the month's release schedule as a vertical list with complete bill titles and 44px tap selection buttons.

## Why switching bills preserves the schedule tab and carries the clicked date

Switching bills stays on the schedule tab, and clicking a day with an existing bill switches to that bill while carrying the clicked day in the address.

When an operator clicks a calendar day holding an existing bill, the schedule tab navigates to that bill on the schedule tab rather than leaving the operator on the current bill. Passing `schedule` as the tab parameter keeps the schedule view active across bill switches, and carrying the clicked date parameter ensures the target day remains selected.
