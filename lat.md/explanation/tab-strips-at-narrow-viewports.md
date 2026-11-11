---
lat:
  mode: explanation
---
# Tab strips at a narrow viewport

A tab strip is one flex row whose triggers carry `shrink-0` and `whitespace-nowrap`, so on a 320px screen a strip wide enough pushes the whole page sideways rather than growing taller.

## Why the strips wrap rather than scroll

`app/frontend/components/ui/tabs.tsx` lets the list wrap onto a second row rather than scroll.

`overflow-x-auto` on the list was the rejected alternative: it would clip the active tab's underline, which sits below the trigger's own box at `bottom-[calc(-1*var(--neo-border-width))]`, so the reader would lose the one mark saying which tab is open.

Dropping `shrink-0` and `whitespace-nowrap` from the trigger is the other way to stop the overflow, and it was rejected: a label broken across two lines inside its own tab makes the strip's rows different heights and the underline ragged. Wrapping whole tabs keeps each label on one line.

## What the four pages measure

`spec/system/reader_tab_strips_narrow_spec.rb` visits four pages at 320px — the representatives list, a representative's own page, notifications, and an organization membership — measuring the strip's reach and the page's own width.

The check has to run in a browser: jsdom has no layout engine, so an overflowing strip and a wrapped one are the same zero-width markup there. The helper in `spec/support/narrow_viewport_helpers.rb` narrows the viewport through the DevTools metrics override, because `resize_to` stops at Chrome's own 500px floor and reports success.

Two of the four carried a second overflow that was not the strip, and both are fixed rather than excused. The "Enable push notifications on this device" button laid out 375px wide because `Button`'s base classes set `shrink-0` and `whitespace-nowrap`, so at this one call site the label wraps and the height follows it. The membership header's middle column had no `min-w-0`, so the organization's name floored the row at its own width and pushed the Leave button past the edge; the column may now shrink and the name truncates.

The Bill Creator's strip was found overflowing first and fixed at that one call site, on the argument that the fix's blast radius should match the surface under test. These four were never measured until the narrow-viewport sweep, and all four overflowed, which is what moved the fix into the primitive.

## Why the layout backstops need a real browser

The layout rules held back as backstop rows are measured in a browser at a 320-pixel viewport, and none of them can be checked below one.

jsdom has no layout engine, so `scrollWidth` and `clientWidth` are both zero
there and a clamped element and an unclamped one are both zero pixels tall.
Every assertion of this kind would pass against any markup at all. What the
backstops cover is the same two shapes on each surface: no horizontal page
scroll with real content at that width, and a very long string — a name or a
quoted phrase — clamped to its allowed number of lines in every shipped theme
while staying selectable.

## Text-node overflow diagnostics

Text can exceed a fitting element's box, so the overflow diagnostic measures text ranges as well as element rectangles.

An inline flex button with unwrapped text can keep its own bounding rectangle inside the viewport while its text increases the document's scroll width. An element-only scan then reports no culprit. [[spec/support/narrow_viewport_helpers.rb#NarrowViewportHelpers#overflowing_elements]] measures nonblank text nodes with a Range and reports their parent elements. Content clipped or scrolled by its own container remains excluded because it does not widen the page. The same diagnostic serves every narrow layout check rather than depending on the button that first exposed the gap.

## What the four standalone admin pages measure

`spec/system/admin_pages_narrow_spec.rb` visits `/admin`, `/admin/categories`, `/admin/locales` and `/admin/llm_settings` at 390px, the width the admin mobile-web pass names, and again at 320px.

The second width comes from the specs themselves rather than from that pass: 320px is `NarrowViewportHelpers::NARROW_VIEWPORT_WIDTH`, the narrowest viewport the UI contract names, reused here rather than restated.

Each page is measured three ways: the document's own laid-out width against the room it has, the height and right edge of the page's primary control, and — on the one page with a table — whether the sideways scroll belongs to a container rather than to the document.

The shared `Table` primitive in `app/frontend/components/ui/table.tsx` wraps every table in a `relative w-full overflow-x-auto` div. The categories table therefore scrolls inside that div rather than widening the document, and the div is the convention the rest of that pass copies rather than each admin surface carrying an overflow rule of its own.

The 44px floor is already in the primitives these pages use: `--control-height` in `app/frontend/styles/tokens.css` is 2.75rem and `Button`'s default size reads it, while `Button`'s `sm` size is `h-11` below the `sm` breakpoint and `h-8` above it.

A control inside that scroll container is measured for its height but not for its right edge. The Rename button in the categories table reaches 599px in a 390px viewport, which is where a control in a sideways-scrolling table belongs, and the same rule already governs which elements `overflowing_elements` reports.

Only the locales page moved the document. Its per-locale row was one non-wrapping flex line of four parts — a 176px label, the bar, a 48px count and the sample-address button — measured at 500px wide against 375px of room, with the button running from 312px to 500px. Below the `sm` breakpoint that row is now a column, and the count and the button share a line inside a wrapper that becomes `display: contents` at `sm` and above, so the row above that breakpoint is the same four-item flex line it was.

The narrow locales example measures the Summarization control and expanded panel for its Baltimore row at both widths. The page can render one such control per locale, so the target row is identified by the panel ID exposed through that button's `aria-controls` attribute.
