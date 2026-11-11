---
mode: explanation
summary: "Why PerBillGrid pins the current bill outside react-virtual's window, why it is wrapped in memo and skipped by the React Compiler, and how its aria-rowindex/aria-rowcount accounting works across the pinned row and the virtualized rows."
status: agent-extracted
related: []
---
<!-- vale Vale.Spelling = NO -->

# PerBillGrid mechanics

## Why only visible rows are drawn, with the current bill pinned outside that

Bill-by-bill table for a pipeline run. Only visible rows are drawn
(virtualized); the current bill is pinned as the first row outside that.
Sub-pieces live in ./per-bill-grid/.

## Why currentStage/stagesSucceeded/stagesTotal are props, not computed per row

Run-level stage info (current stage, succeeded/total) comes in as props
rather than computed per row, so scrolling doesn't redo the sums every
frame.

## Why runStatus is threaded down to RowCells

The run's own status. RowCells needs it to tell a stage in progress from
the stage a finished run stopped at; see the note on IRowCellsProps.

## Why billIdByExternalId is optional

Maps a row's external_id to its numeric id, built from the picker's bill
list. Missing (rare — bill dropped from the current session) means no
"View" link on that row.

## Why pinnedRow is filtered out of virtualRows rather than reordered

Every non-pinned row keeps its original sort_order — useVirtualizer only
decides which of them to actually render.

## Why the React Compiler skips this component

useVirtualizer hands back functions that cannot be cached between
renders, so the React Compiler skips this component on purpose. There is
no fix to make in the code.

## Why measureElement is disabled on Firefox

Firefox reports a height of 0 for rows that have just appeared, so there
we skip measuring and use the estimated size instead.

## Why aria-rowcount sits on the table, and why one TooltipProvider covers every row

aria-rowcount must sit on the table, not a rowgroup — so header, pinned
row, and scrolling rows share one real `<table>` (role is implicit) so
screen readers can say "row N of M".

One TooltipProvider covers the pinned row and every scrolling row (each
has two tooltips: cut-off title, start time) — same pattern as
BillScheduleCalendarDay and DistrictLabel.

Packed rows use a short delay so a quick hover shows the full title
without waiting.

## Why the column headings sit outside the scrolling area

The column headings sit outside the scrolling area, so they stay on
screen however far down you scroll.

## Why the pinned row and the first scrolling row each draw their own bottom border

Pinned row and the first scrolling row each draw a bottom border for a
different join (pinned→scrolling vs row→row) — same 1.5px line, so it
never looks doubled.

## Why the scroll container's height is capped as a viewport share, not a fixed px

Height is capped as a share of viewport (60vh), not a fixed px, so the
table doesn't shrink too small on a tall screen or run off a short
Chromebook.

## Why aria-rowindex accounts for the header and pinned row

aria-rowindex starts counting at 1 and has to include the header row,
plus the pinned row when there is one.

## Why ResourceCachePanel indexes mirrors by tier

Indexed by tier for O(1) lookup; any tier missing from mirrors still
renders as a "Not cached" row, in the fixed order.

## Why ResourceCachePanel wraps its table in one TooltipProvider

Tooltips need a TooltipProvider above them (Radix/shadcn) — one here
covers every row's hover text, same pattern as PerBillGrid and
BillScheduleCalendarDay.

## Why PerBillGrid is wrapped in memo

BillCreatorPipelineLlm re-renders on every poll and live update, but every
prop here is a simple value or an already-stable object.

## Why the scroll height comes from a spacer row, not a wrapper div

The scrolling `<tbody>` needs a child taller than itself, or there is
nothing to scroll: the visible rows are `position: absolute` and
therefore out of flow, so they contribute no height.

The obvious way to do that is a wrapper `<div>` inside the `<tbody>`
holding `height: getTotalSize()`, and that is what this grid did until
it was replaced. It is invalid HTML. The content model of `<tbody>` allows
only `<tr>`, and React reports the violation as a hydration error on
every load of the pipeline tab.

Instead the `<tbody>` itself carries `position: relative`, so it is the
containing block the absolutely positioned rows resolve against, and an
`aria-hidden` spacer `<tr>` carries the total height. A `<tr>` is a legal
child of `<tbody>`, an empty one is legal HTML, and with `display: block`
and a height it provides exactly the scroll extent the wrapper div did.
The `<tbody>` has no padding or border, so the rows' offsets are
unchanged by resolving against it rather than against the old wrapper.

The same content model applies one level down: the cells in
`RowCells` are `<td>`, not `<div>`. Laying the row out with CSS grid does
not change what may appear inside a `<tr>` — a grid item is blockified,
so a `<td>` lays out identically to the `<div>` it replaced.

`PerBillGrid.test.tsx` pins both rules by walking the rendered tree and
asserting no rowgroup holds a non-`<tr>` child and no row holds a
non-cell child, so a future edit that reaches for a `<div>` fails
instead of adding console noise.
