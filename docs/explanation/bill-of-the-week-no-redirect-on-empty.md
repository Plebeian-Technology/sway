---
mode: explanation
summary: "Why BillOfTheWeekController#show renders the page with no bill rather than redirecting when a locale has nothing featured."
status: agent-extracted
related: []
---

<!-- vale Vale.Spelling = NO -->

# Why an empty Bill of the Week stays on the page

A locale with no featured bill used to redirect to the bill list. That
carried the reader somewhere they had not asked to go, and because
switching locale loads the page afresh, they watched the bill disappear,
a nearly blank page flash up, and a navigation they never asked for land.

`BillOfTheWeekController#show` now renders the page with no bill instead,
so the locale picker stays on screen and the reader can switch locale
again without an unexpected jump.

## Why the empty-state copy names the jurisdiction

`PARITY_COPY.billOfTheWeek.noneForLocale` is the version that names the
place. Switching to another jurisdiction used to bounce the reader over to
the bill list — somewhere they never asked to go, with nothing saying why.
The page now stays put, so it has to name the jurisdiction that has
nothing featured; otherwise an empty screen just looks like a page that
failed to load.
