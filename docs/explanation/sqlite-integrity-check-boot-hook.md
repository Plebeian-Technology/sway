---
mode: explanation
summary: "Why the SQLite integrity check's boot wiring is a thin initializer hook with the real logic living in lib/."
status: agent-extracted
related: []
---

<!-- vale Vale.Spelling = NO -->

# Why the integrity check initializer is a thin hook

`config/initializers/sqlite_integrity_check.rb` runs SQLite's `PRAGMA
quick_check` (a fast corruption scan) when the app boots. This file is only
a thin hook: the real logic lives in `lib/sqlite_integrity_check.rb` so
tests can exercise each environment's branch without restarting Rails.
That module's docstring describes what happens in each environment.
