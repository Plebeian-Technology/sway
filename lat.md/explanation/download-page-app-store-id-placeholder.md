---
lat:
  mode: explanation
---

# Why /download degrades instead of erroring with no App Store id set

`APPLE_APP_STORE_ID` is the one setting on the marketing download page that is read unstubbed by its own request spec — this is the plan's own truth: the page must still render, with the placeholder, when no store id is set.

The partial's own guard skips the App Store anchor entirely for a value carrying `<` or `>` — the literal placeholder text — rather than building a broken link out of it.
