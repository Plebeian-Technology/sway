---
lat:
  mode: explanation
---

# Shared request error parameters

The shared `params` prop exposes only the locale id needed by the page, not arbitrary request values.

## Raw error parameters never reach shared page props

[[app/controllers/application_controller.rb#ApplicationController]] includes `sway_locale_id` in its shared `params` object but deliberately omits `params[:errors]`. A crafted query could otherwise inject text into rendered props, and no client reads that value; flash remains the supported error channel.
