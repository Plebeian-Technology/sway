---
mode: explanation
summary: "Why SeedSwayLocale.run's returned array deliberately includes locales seed_or_skip? left alone."
status: agent-extracted
related: [docs/reference/seedable-module.md]
---

# Why `SeedSwayLocale.run` returns skipped locales too

The array `SeedSwayLocale.run` returns includes skipped locales BY DESIGN. A
skipped locale is either (a) a new record that `seed_or_skip?` let through
(it returned `false`), so the record was saved and stamped normally, or (b)
an already-persisted record that was edited by hand since the last seed,
which makes `seed_or_skip?` return `true` — that record is already saved
from earlier runs and is still safe for downstream seeders (`SeedLegislator`,
`SeedBill`) to attach to as a parent. Downstream seeders care only about
WHICH locale a record belongs to, not the locale's attribute values, so
passing a skipped locale through is correct behavior.
