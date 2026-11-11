---
mode: explanation
summary: "Why config/environments/test.rb pins SWAY_RELEASE_SHA as a real ENV assignment before Rails boots, instead of relying on spec/rails_helper.rb."
status: agent-extracted
related: [docs/reference/release-metadata-values.md]
---

<!-- vale Vale.Spelling = NO -->

# Why the release SHA is pinned before Rails boots in test

The release sha is pinned before Rails boots in test, so it is set for every
process that loads `config/environments/test.rb` — `dip run bundle exec
rspec` and a host run alike — not only the ones that happen to go through
`spec/rails_helper.rb`.

`Sway::Release` reads `ENV["SWAY_RELEASE_SHA"]` directly (never Rails
config), so this has to be a real `ENV` assignment. Unset, every Inertia
render spawned two `git rev-parse HEAD` subprocesses (~3.9ms) and made the
release props vary with whatever HEAD happened to be checked out; pinning
makes both specs and props deterministic. `||=` leaves an
explicit operator override (a live-verification run, say) alone.
