---
mode: explanation
summary: "Why BillSchedule derives selectedDate fresh on every render instead of storing it, why picking an existing bill on a calendar day switches to it, and why the click-to-pick-a-date path uses only: [] instead of a full reload."
status: agent-extracted
related: []
---
<!-- vale Vale.Spelling = NO -->

# BillSchedule mechanics

## Why BillSchedule works the way it does

The screen for scheduling the Bill of the Week. It holds the hand-built
calendar and the sidebar of upcoming and not-yet-scheduled bills.

Saving works the same way as the older
`app/frontend/components/bill/creator/scheduler/BillScheduleCalendarSelectedBill`.

`router.put("/bill_of_the_week_schedule/0", { scheduled_release_date_utc, bill_id, tab_key })`.

Choosing a different bill loads the creator page again, mirroring the
older `handleChangeBill` flow.

## Why selectedDate is derived fresh on every render, not stored in state

Derived fresh on every render from page data + the address bar, rather
than stored once in state — switching bills keeps this component's React
state alive, so it's never rebuilt.

A stored date kept showing the PREVIOUS bill's date with "Schedule bill"
still clickable, so one click could schedule the new bill for the old
date.

Deriving it here also lets the sidebar clear the date by writing an empty
value — which now becomes null instead of falling back to the last one.
`params.get` reads the current address each time.

## Why handleSelectBill passes "schedule" as the tab

This picker sits on the Schedule tab, so pass "schedule" as the tab part
of the address and stay on that tab.

## Why clicking a day with an existing bill switches to it

Clicking a day that already has a bill switches to it, matching the older
BillScheduleCalendar.onDaySelect; handleSelectBill carries the clicked
date along in the address.

## Why the plain date-pick path uses `only: []` with preserveState

Otherwise puts the clicked date in the address, where the derived
selectedDate above picks it back up.

Empty `only: []` means "change the address, ask the server for nothing" —
the same trick Notifications.handleTabChange uses.

preserveState keeps the creator shell alive; params.add would leave that
off and rebuild it.

## Why BillScheduleCalendar is a hand-built calendar, not react-day-picker

A month calendar written by hand. It deliberately does not use
react-day-picker. Each day cell is drawn by `BillScheduleCalendarDay`,
which decides its stamp colour.
