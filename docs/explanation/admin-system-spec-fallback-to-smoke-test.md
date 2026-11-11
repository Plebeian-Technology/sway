---
mode: explanation
summary: "The convention several admin system specs follow: stop iterating on a flaky interactive widget and fall back to a smoke test rather than fighting the interaction indefinitely."
status: agent-extracted
related: []
---

<!-- vale Vale.Spelling = NO -->

# Falling back to a smoke test when an interaction keeps fighting back

`spec/system/admin_llm_settings_spec.rb` and `spec/system/admin_categories_spec.rb`
both carry the same escape hatch: if a Radix Select, an inline rename
control, or a confirm dialog keeps fighting back in headless Chrome, stop
iterating on driving the full interaction and fall back to a smoke test
instead — visit the page, see the heading and the affected row, and check
the database directly — then file a follow-up issue rather than spending
more time forcing the interaction to behave.

Both specs currently do the full round trip; this is the fallback plan
recorded ahead of time, not something either spec has needed yet.
