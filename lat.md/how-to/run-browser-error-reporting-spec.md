---
lat:
  mode: how-to
---

# Running the browser error reporting spec standalone

`spec/system/browser_error_reporting_spec.rb` checks that a real error reported from a real browser really arrives at the local error collector — no Ruby-side stub is on the path, so this is the only honest check.

`dip run rspec` runs it and sets everything up automatically. To run it alone on the macOS host, with `dip run dev` already up:

1. Export the collector DSN from `config/rustrak_project.key`:
   ```bash
   export VITE_RUSTRAK_DSN="$(cat config/rustrak_project.key)"
   ```
2. Build the frontend bundle in test mode:
   ```bash
   pnpm vite build --mode test
   ```
3. Run the system spec with host Rails enabled:
   ```bash
   SWAY_ALLOW_HOST_RAILS=1 RAILS_ENV=test SWAY_DATABASE_PASSWORD='testing123!' \
     VITE_RUBY_PORT=3099 SE_CACHE_PATH=/tmp/selenium \
     bundle exec rspec spec/system/browser_error_reporting_spec.rb
   ```

## Why both the build and Rails need the collector address

The collector address must reach two separate places: the built frontend bundle (so the browser SDK knows where to send reports) and Rails (so the page's Content-Security-Policy connect rule allows the browser to reach it).

Setting `VITE_RUSTRAK_DSN` before the build satisfies the first. Missing the second — the CSP connect rule — is how this went wrong the first time: the browser tried to send and was refused.

## Why the precondition check reads the built assets, not the source

`built_bundle_reports_errors?` reads the built JS assets rather than the source, because what matters is what the browser will actually load, and Vite writes the collector address in at build time.

It asks `RailsVite.config.build_dir` for the build directory rather than naming one literally. A verify lane and `dip run rspec` each build into their own `vite-test/run-<id>` directory, so a literal `"vite-test"` glob would match nothing under either — the example would silently skip, and a skip reads as a pass.
