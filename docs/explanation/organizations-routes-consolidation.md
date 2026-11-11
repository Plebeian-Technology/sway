---
mode: explanation
summary: "Why Organizations routes are declared once with nested membership/position routes, and why :update on the top-level resource is admin-only."
status: agent-extracted
related: []
---

<!-- vale Vale.Spelling = NO -->

# Why Organizations routes are declared once

Organizations are declared once, with nested membership/positions routes —
a duplicate standalone declaration used to produce clashing top-level
index/show/create routes.

`:update` is admin-only: it renames a canonical
Organization from the Bill Creator org panel. The name is locale-scoped and
shared, so renaming changes the org for every bill in `current_sway_locale`.
