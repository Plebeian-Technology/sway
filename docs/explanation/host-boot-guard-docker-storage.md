---
mode: explanation
summary: "Why config/boot.rb refuses to boot Rails on the host outside production, and what it protects against."
status: agent-extracted
related: []
---

<!-- vale Vale.Spelling = NO -->

# Why Rails refuses to boot on the host

The dev/test SQLite databases live in the `sway_storage` Docker named volume
(see `.dockerdev/compose.yml`). Running Rails on the host hits a different
`storage/` directory entirely and silently diverges, masking failures like
`Could not find table 'sway_locales'` after a successful dip-side seed.

`config/boot.rb` forces everything not explicitly production through `dip`:
it aborts before Rails finishes booting unless `IS_DOCKER` is set,
`RAILS_ENV` is `production`, or an operator has explicitly set
`SWAY_ALLOW_HOST_RAILS` to bypass the guard (rare).
