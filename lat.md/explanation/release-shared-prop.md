---
lat:
  mode: explanation
---

# Release metadata on shared pages

Every Inertia page receives the running build metadata so the shared logo can identify the deployed version.

## The release prop is shared across pages

[[app/controllers/application_controller.rb#ApplicationController]] shares `Sway::Release.to_sway_json` on every page. The value is constant for a production process; its development fallback reads the current git revision so a long-running server reports a commit made after it booted.
