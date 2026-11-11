---
lat:
  mode: explanation
---

# Why the routes.rb constant check reads the file, not a reload

`config/routes.rb` must assign no constant at the top level.

Ruby warns "already initialized constant" when a boot loads that file more than once, and zero warnings is the baseline `spec/config/routes_top_level_constants_spec.rb` holds it to.

## Why this reads the file rather than watching a redraw

With a deliberately reintroduced top-level constant, the warning appears during the rspec boot, before the first example, and `Rails.application.reload_routes!` emits nothing at all.

So no example can observe it by watching a reload — an earlier attempt that captured stderr around a redraw passed with the warning plainly on screen. The file's text is the only place the cause is visible from inside a spec.

Two consequences of that measurement worth keeping:

- A `rails runner` boot does not warn either, so the doubled load belongs to
  the rspec boot specifically.
- The `$VERBOSE` silencing `spec/routing/catch_all_redirect_spec.rb` used to
  wrap around its two redraws was silencing nothing, which is why it was
  removed.
