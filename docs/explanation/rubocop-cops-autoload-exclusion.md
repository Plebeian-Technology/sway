---
mode: explanation
summary: "Why config/application.rb excludes lib/cops from autoload_lib, so Zeitwerk doesn't eager-load RuboCop plugins in production."
status: agent-extracted
related: []
---

<!-- vale Vale.Spelling = NO -->

# Why `cops` is excluded from `autoload_lib`

`cops` holds RuboCop plugins (e.g. `Sway/InertiaMatcherRequired`). RuboCop
loads them directly via the `require:` directive in `.rubocop.yml`; they are
NOT app code. They are ignored in `config.autoload_lib(ignore: %w[assets
tasks cops])` so Zeitwerk doesn't eager-load them in production, where
`rubocop` is absent (a dev/test-only gem) and the class body's
`RuboCop::Cop::Base` reference raises `NameError` at boot.
