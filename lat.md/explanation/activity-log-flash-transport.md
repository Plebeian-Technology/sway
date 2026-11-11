---
lat:
  mode: explanation
---

# The activity log's flash transport

An entry logged during an Inertia request rides back to the page in `flash[:activity_log_entry]`. When that write overflows the session cookie, a rescue sends `flash[:activity_log_error]` instead and `ActivityLogPanel` shows a banner.

The fallback carries only the entry id and the error class, so it stays well under the cookie's size limit; the banner links back to the entry on the current pipeline tab.

## Why a test-only controller proves the round trip

`InertiaFlashProbeController` exists only for tests: `spec/rails_helper.rb` requires it and `config/routes.rb` draws its two routes inside the `Rails.env.test?` block.

Its `trigger` action calls `PipelineActivityLogger.log_orphan_run_deleted!` and renders an Inertia page, so `spec/requests/pipeline_activity_logger_inertia_flash_spec.rb` watches a real entry travel through the flash and `inertia_share` and come back out as a page prop, with no fake request standing in for any part of the path.

Both actions skip the sign-in, admin-gate, API-route and locale-session `before_action`s. The specs that hit them are about the flash, and a dependency on authentication being set up first would give each of them a way to fail that has nothing to do with what it checks.

## Why the dispatch lives outside the logger

Deciding how an entry reaches a reader — the flash on an Inertia request, the cable otherwise — is `PipelineActivityLogger::Transport.dispatch`, not a branch inside the logger itself.

Separating them gives every caller that only wants a row written a place to
silence the delivery without silencing the write. Outside a request there is no
flash to ride, so the async branch broadcasts over the cable, and a spec about
retention or cleanup would otherwise be broadcasting on every example for no
reason.

## Why the current request is held in `Current`

Current request context tells the activity logger whether to use Inertia flash or ActionCable.

[[app/controllers/application_controller.rb#ApplicationController]] stores the request in `Current.request`. `CurrentAttributes` clears the value between requests; a bare thread-local could leak when Puma reuses a thread.

## Why the fallback is tested without a real overflow

Staging a real transport failure in a browser spec means producing, on every run, an entry the session cookie cannot hold. `trigger_flash_error` sets `flash[:activity_log_error]` directly instead and redirects to the bill's pipeline tab.

That exercises the same flash round trip through `inertia_share` and the same `ActivityLogPanel` rendering a real overflow would, without the failure itself; `spec/system/admin_activity_log_error_banner_spec.rb` drives it. What `spec/services/pipeline_activity_logger_spec.rb` covers on its own is the rescue's last resort: a request whose flash raises on every write, where the doubled failure is logged once with both error classes.
