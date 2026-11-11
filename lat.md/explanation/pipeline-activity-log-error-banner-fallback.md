---
lat:
  mode: explanation
---

# The activity log error banner fallback

`for_flash` mode already drops the raw model response to keep entries under the session cookie's ~4KB cap (see `pipeline-activity-log-serialize-entry-quirks.md`).

When an entry still overflows the cookie despite that trim — for example an `llm_json_parse_failure` entry with a 4000-character `raw_excerpt` — the normal `flash[:activity_log_entry]` write in `PipelineActivityLogger::Transport.dispatch_inertia` raises. The rescue for that write sets `flash[:activity_log_error]` instead, carrying only the entry id and the error class name.

`ActivityLogPanel.tsx` renders a red, destructive banner when `flash.activity_log_error` is present, linking back to the entry on the current pipeline tab.

## Why InertiaFlashProbeController exists and skips sign-in

`InertiaFlashProbeController` is a controller that exists only for tests, loaded only in the test environment (see the conditional block in `config/routes.rb`).

Its `#trigger` action renders an Inertia page and calls `PipelineActivityLogger.log_orphan_run_deleted!`, so a spec can watch a flash message travel end to end through Inertia and back without swapping in a fake request. `#trigger_flash_error` is the sibling action described above. Both actions skip the normal sign-in and admin-gate `before_action`s, so the specs that hit them do not depend on authentication being set up first.

## Testing the fallback without a real overflow

Staging an actual transport failure to exercise this path is expensive to set up reliably in a browser spec.

Instead, `spec/system/admin_activity_log_error_banner_spec.rb` uses a test-only probe endpoint (`spec/support/inertia_flash_probe_controller.rb`, wired in `config/routes.rb`) that sets `flash[:activity_log_error]` directly and redirects to the bill edit page. That exercises the same flash round trip through `inertia_share` and the same `ActivityLogPanel` rendering that a real overflow would, without staging the failure itself.

The rescue's own behavior — that it fires on a write failure — is covered separately in `spec/services/pipeline_activity_logger_spec.rb`.

## Why each delivery path has its own rescue

One shared rescue used to catch both the flash write and the WebSocket broadcast, and logged the same thin warning either way.

That broke the promise that an operator can see what happened when they paste a summary, decide an organization position, or force-fail a run: the audit row was saved, but no banner and no error appeared, so the operator would paste again and create a duplicate entry. Now the failure puts a small marker in the page response — just the entry id and the error class, so it stays well under the cookie size limit — and logs a warning with enough context to debug. The operator gets a banner; whoever is on call gets something to read.

## Why a doubled failure logs both error classes on one line

The fallback write (`flash[:activity_log_error] = ...`) is wrapped in its own rescue: if the flash is broken beyond saving, the first failure falls back to the log alone.

That inner rescue must not quietly swallow a second failure — this write exists so the operator sees something when the first one fails, and failing twice in silence defeats the point. `log_exception` only takes one exception, so both error classes are logged on a single line with `SwayLogging.error` instead, so whoever reads the log can tie the two together.

## The banner's link resolves against the current path

The link inside the banner's `AlertDescription` stays on the current pipeline tab and adds a highlight parameter.

Its `href` is written as a bare `?...`, so the browser resolves it against the current path rather than the controller building an absolute URL — the spec checks the full resolved URL still names the pipeline tab.
