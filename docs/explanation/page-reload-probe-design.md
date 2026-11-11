---
mode: explanation
summary: "Explains why PageReloadProbe plants a window value to prove a browser kept the same document instead of reloading, and why plant_reload_probe! verifies its own mark before returning."
status: agent-extracted
related: []
---

# Why `PageReloadProbe` proves the SAME document, not just that new text arrived

Sway's rule is that refreshing is never part of a workflow: a screen
showing data that changes has to update itself (partial reload, a live
socket message, an in-page tab change) rather than reload the whole
document. A Capybara example that waits for new text to appear proves the
text ARRIVED. It does not prove HOW it arrived — a full document load
satisfies every one of those waits while breaking the rule outright. That
is not hypothetical: hands-on testing caught the Bill Creator
loading itself three times with nobody touching it.

`PageReloadProbe` proves the stronger claim by planting one value onto
`window`. Everything React does keeps that value in place — a partial
reload, a live message over the socket, a tab change inside the page. A
full document load builds a brand new `window`, and the planted value is
gone. Checking that the value survived is checking that the document
itself never changed.

## Why `plant_reload_probe!` checks its own mark before returning

`plant_reload_probe!` reads its own mark back immediately after planting
it, rather than trusting the write succeeded. Without that check, a probe
that never took for some reason (a race with page teardown, a `window`
that was not what was expected) and a page that later genuinely reloaded
both end up reading `nil` at `expect_no_full_page_load!` — indistinguishable
results for two very different failures. The immediate self-check turns "a
probe that never took" into a raised error at plant time, so a later
`nil` can only mean one thing: the document actually reloaded.
