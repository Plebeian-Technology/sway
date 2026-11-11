---
mode: explanation
summary: "Why reportOnce exists and how its two dedupe limits (per-tab memory, per-browser storage) keep a single build/settings fault from flooding Sentry."
status: agent-extracted
related: [docs/explanation/frontend-test-infrastructure-notes.md]
---

# Why reportOnce exists

Tell Sentry about a fault that belongs to an operator, not to the reader.

A fault in the build or the settings is the same fault for everybody.
Reporting it from the browser means every visitor reports it, so a single
mistake can turn into thousands of messages and use up the month's
allowance. Two limits keep that in check:

- once per tab, held in memory
- once per `windowMs` per browser, held in local storage

The key also becomes Sentry's fingerprint, so every copy that does get
through lands in ONE issue instead of a new one each time.

Returns whether anything was sent, which is what makes it testable.
