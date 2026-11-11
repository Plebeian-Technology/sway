---
lat:
  mode: explanation
---

# Why LocalErrorCollector reads back from the real collector process

`LocalErrorCollector` (`spec/support/local_error_collector.rb`) reads back from the error collector already running on this machine, using the project and the token that `dip run dev` set up.

It creates nothing: no account, no project, no token. Provisioning those is `dip run dev`'s job, not the spec's.

This is the only way to check the BROWSER half of error reporting end to end — the browser sends its own report directly, with no Ruby code on the path to stub. `FakeErrorCollector` (see `docs/explanation/fake-error-collector-design.md`) checks what the RUBY side puts on the wire; `LocalErrorCollector` checks that a browser-sent report actually arrived and was stored, by asking the real collector.

## Why an unavailable collector skips the spec instead of failing it

`.unavailable_reason` returns a SENTENCE naming which precondition is missing, or `nil` when the spec can run — never a bare flag.

A suite that skips forever with no reason printed is worse than one that fails loudly, so the reason always names the fix (`dip run dev`, `bin/rustrak-mcp-token`, etc.) rather than just reporting "unavailable".
