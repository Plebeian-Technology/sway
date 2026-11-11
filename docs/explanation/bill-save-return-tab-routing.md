---
mode: explanation
summary: "Explains why PATCH /bills/:id carries a return_tab param and redirects back to whichever Bill Creator tab the save came from."
status: agent-extracted
related: []
---

<!-- vale Vale.Spelling = NO -->

# Why a bill save carries its own return tab

`PATCH /bills/:id` is shared by the Creator tab's bill form and the Summary
tab's Save summary button. Its success branch used to always redirect to
the Creator tab. An operator working on the Summary tab who clicked Save
landed on a different tab — scrolled by `preserveScroll` to the same offset
on content they never asked for, with any draft positions they were
triaging now off screen, costing a click plus a page load to get back.

The endpoint cannot tell which tab sent the request on its own, so the tab
has to travel with the request: both the bill form and the Summary tab's
Save summary button send a `return_tab` param, and the controller redirects
back to whichever tab named itself. A refused save follows the same rule —
it returns to the tab it came from, because the Summary tab keeps no other
copy of the operator's unsaved text.
