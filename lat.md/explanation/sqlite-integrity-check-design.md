---
lat:
  mode: explanation
---

# SqliteIntegrityCheck design notes

`SqliteIntegrityCheck` (`lib/sqlite_integrity_check.rb`) runs SQLite's `PRAGMA quick_check` on every SQLite database configured for the current Rails env.

## Why it lives in lib/

It lives in `lib/`, rather than under `app/`, so the spec can exercise each environment branch without restarting Rails.

## Why the busy-lock timeout matches database.yml

`BUSY_TIMEOUT_MS` matches the connection `timeout` in `database.yml`, so a busy database (for example, SolidQueue writing the queue DB during boot) gets waited out instead of failing instantly.

## Why a busy lock is skipped, not treated as a failure

`.collect_failures` rescues `SQLite3::BusyException` and skips that database with a warning rather than aborting.

A locked DB in active use by another process is contention, not corruption, and `.quick_check` has already waited out `BUSY_TIMEOUT_MS` for the lock to clear — skipping with a warning means a short-lived lock never aborts the web process.

## Why production logs and never raises

`.run` raises in development (loud, aborts boot so operators can repair) but only logs and calls `Sentry.capture_message` in production. Raising in production would create a boot loop. The Sentry alert routes to oncall.
