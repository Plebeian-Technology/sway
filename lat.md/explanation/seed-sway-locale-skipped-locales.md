---
lat:
  mode: explanation
---

# Why SeedSwayLocale.run returns skipped locales too

The array `SeedSwayLocale.run` returns includes skipped locales BY DESIGN.

A skipped locale is either (a) a new record that `seed_or_skip?` let through (it returned `false`), so the record was saved and stamped normally, or (b) an already-persisted record that was edited by hand since the last seed, which makes `seed_or_skip?` return `true` — that record is already saved from earlier runs and is still safe for downstream seeders (`SeedLegislator`, `SeedBill`) to attach to as a parent. Downstream seeders care only about WHICH locale a record belongs to, not the locale's attribute values, so passing a skipped locale through is correct behavior.

## Child table synchronization on skipped locales

Child legislative session synchronization executes unconditionally even when scalar attributes on `SwayLocale` are skipped.

The `seed_or_skip?` guard protects scalar attributes (`time_zone`, `icon_url`, `sample_street`) and timestamps (`updated_at`, `last_seeded_at`) from being overwritten by YAML defaults after manual out-of-band edits. In contrast, `LegislativeSession` records represent authoritative governing intervals stored in a separate table (`legislative_sessions`) without `touch: true`. Synchronizing child sessions ensures that queries like `Bill.current_session` resolve active intervals while preserving manual scalar customizations on the parent `SwayLocale` row, mirroring the child-synchronization pattern used in `SeedLegislator`.
