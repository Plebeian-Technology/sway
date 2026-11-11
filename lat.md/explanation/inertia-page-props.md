---
lat:
  mode: explanation
---

# Shared Inertia page props

The global page-props type mirrors data that Rails shares with every Inertia page.

## The page-props interface covers shared flash and errors

[[app/controllers/application_controller.rb#ApplicationController]] shares flash and user context on page responses; Inertia also places redirect validation errors on its page props. The `IPageProps` interface gives page consumers a common type for those shared values instead of requiring local casts.
