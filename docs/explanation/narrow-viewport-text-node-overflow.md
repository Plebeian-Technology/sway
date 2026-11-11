---
mode: explanation
summary: "Why overflowing_elements() (spec/support/narrow_viewport_helpers.rb) has to walk text nodes, not just elements, to name the thing causing a 320px page-scroll failure."
status: agent-extracted
related: []
---
<!-- vale Vale.Spelling = NO -->

# Why the 320px overflow diagnostic has to look at text nodes

`overflowing_elements()` names the widest element reaching past a narrow
viewport's right edge, so a failing `expect_no_horizontal_page_scroll!` can
say what to fix instead of only reporting a total. It used to look only at
Elements: it queried `body *` and read each element's own
`getBoundingClientRect()`.

That missed a real case. `BillCreatorOrganizations`' "Save Supporting/Opposing
Arguments" button and `PipelineActionButtons`' "Run pipeline for bill …"
button are both `inline-flex` buttons with `whitespace-nowrap` (the shared
`Button` component's default) holding an icon plus a text run. When that text
run is wider than the button's own box, the browser does not grow the
button's box to match — the button stays whatever width its layout gave it —
but the button's `scrollWidth` (and everything up the ancestor chain, and
eventually `document.documentElement.scrollWidth`) reflects the wider,
un-wrapped text. No *element*'s own bounding rect crosses the viewport edge in
this case: the button's box fits, and the text itself is a bare DOM text
node, not an element `querySelectorAll` can see. `overflowing_elements()`
came back empty while `expect_no_horizontal_page_scroll!` still failed on the
same page.

Confirmed by measurement (not guessed): in a Chrome instance rendering the
Bill Creator summary tab at 320px, walking `document.body`'s children and
selectively hiding each with `display: none` while re-measuring
`document.documentElement.scrollWidth` narrowed the culprit down to a single
`<button>` whose child `<svg>` icon and following text — `"Save
Supporting/Opposing Arguments"` — extended past the button's own box.
`document.createRange().selectNodeContents(textNode).getBoundingClientRect()`
on that text node's `.right` matched `document.documentElement.scrollWidth`
exactly (318px in a 305px-wide viewport).

`overflowing_elements()` now also walks text nodes with a `TreeWalker`
(`NodeFilter.SHOW_TEXT`), measuring each non-blank node's own `Range` rect. A
hit reports the text node's *parent element* — subject to the same
scroller/`inScroller` filtering already applied to element candidates, so
text genuinely clipped by its own container's `overflow-x: hidden` (a
`line-clamp`ed name, for instance) still doesn't get flagged. Proven
separately: removing such a clamped span from the DOM entirely left
`document.documentElement.scrollWidth` unchanged, confirming clipped content
was never the cause and the fix doesn't start flagging it.

## What this means for other 320px checks

Every spec using `expect_no_horizontal_page_scroll!` before this fix could
have the same failure mode: a real overflow with an empty "widest elements"
list, because the culprit was unwrapped text inside a `whitespace-nowrap`
container rather than an over-wide element box. The fix in
`overflowing_elements()` is general — it isn't specific to the two buttons
that surfaced it — so this was a diagnostic gap in the helper itself, not
a one-off bug in either component.
