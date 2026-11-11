---
mode: explanation
summary: "Two landmines the per-run Vite build directory (SWAY_VITE_BUILD_DIR) guards against: a shared-volume overwrite race between concurrent verify runs, and a silent stale-bundle pass from the wrong shell join operator."
status: agent-extracted
related: []
---
<!-- vale Vale.Spelling = NO -->

# Why the frontend build needs a per-run directory

Two concurrent `dip run verify` runs share one named volume
(`public/vite-test` on the `vite_test` volume). Without a per-run
directory, one run's frontend build can overwrite the bundle another run's
browser specs are reading mid-flight. `SWAY_VITE_BUILD_DIR` gives
each run its own directory, read on both the Node side (`vite.config.ts`,
passed to the `rails()` plugin as `buildDir`) and the Rails side (an
initializer setting `RailsVite.config.build_dir`), so the manifest path and
asset prefix move together with it. Both sides treat an empty value the
same as unset, falling through to the gem's own default, rather than
resolving to `public/` itself — Vite empties its output directory before
building, which would delete every tracked static file under `public/`.

## The second, unrelated landmine: `;` vs `&&`

`.dockerdev/compose.yml` used to join the frontend build to `rspec` with
`;`, so a failed build did not stop the suite from reporting green against
yesterday's bundle. The fix joins them with `&&` instead, so a
failed build stops the run rather than leaving a stale manifest in place —
which otherwise reads as catastrophic breakage (every page assertion times
out at once) rather than the actual cause, a stale bundle.

## Why the initializer filename starts with an underscore

The leading underscore on `config/initializers/_vite_build_dir.rb` is
load-bearing: Rails loads initializers in sorted filename order, and the
underscore sorts before every letter, so this file runs before `inertia.rb`
(`config.version = RailsVite.digest`, which reads the manifest) and
`content_security_policy.rb` (also reads it via `RailsVite`). If the build
directory moved after either, both would resolve the manifest at the OLD
directory — Inertia's version would not match the assets the browser is
actually served, and browser specs would get full reloads or a 409. Pinned
by `spec/config/vite_build_dir_spec.rb` rather than left to memory (the
phase pattern map got this ordering backwards).

`.present?` is used rather than a bare truthy check — an empty string is
present in `ENV` but must fall through to the gem's own default, not become
a literal empty `build_dir` (measured: that wrote straight into `public/`,
wiping the tracked static files there, when a caller declared the variable
without a value rather than leaving it fully unset).
