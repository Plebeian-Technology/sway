---
mode: explanation
summary: "Why the /download page still renders with a placeholder when APPLE_APP_STORE_ID is unset, and why the App Store anchor is skipped for placeholder-shaped values."
status: agent-extracted
related: [docs/explanation/mobile-settings-group-design.md]
---

<!-- vale Vale.Spelling = NO -->

# Why `/download` degrades instead of erroring with no App Store id set

`APPLE_APP_STORE_ID` is the one setting on the marketing download page
that is read unstubbed by its own request spec — this is the plan's own
truth: the page must still render, with the placeholder, when no store id
is set. The partial's own guard skips the App Store anchor
entirely for a value carrying `<` or `>` — the literal placeholder text —
rather than building a broken link out of it.
