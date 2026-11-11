---
mode: explanation
summary: "Explains why the repo's Node version pins must match exactly, must not use a moving alias, and why Ruby/Python are exempt from the same check."
status: agent-extracted
related: []
---

<!-- vale Vale.Spelling = NO -->

# Why the Node version pins must agree exactly

Two files in the repo root name the Node version this project runs on
(`mise.toml` and `.node-version`), and a third lives under `mobile/`. All
three have to name the same one.

## Which file answers depends on the tool

`mise` reads `mise.toml` — and so does every `mise exec` and every
mise-managed shell. `nvm`, `fnm`, and GitHub's `setup-node` action read
`.node-version`. While `mise.toml` said `"lts"` and `.node-version` said
`v24.19.0`, the two named different interpreters, so a test could pass for
one person and fail for another with nothing in the code different.
`mise which node` can resolve to a different version
than `.node-version` asks for, and a Vitest run goes through the first.

`mobile/.node-version` is a third file, and it went unread by anything at
all — it drifted to 24.18.0 while the root moved to 24.19.0, and the mobile
CI lane ran a floating major 22. Three interpreters for one repo, none of
which the version-pin check could see. `mobile-test.yml` now reads the file.

## Neither may be a moving alias

`"lts"`, `"latest"`, and a bare major all resolve to whatever is current on
the day, so the gap between the files widens on its own — and the next
widening can cross a major version, where the failure stops being cosmetic.
A version the check accepts is one somebody chose, matched with
`\A\d+\.\d+\.\d+\z`.

## Why Ruby and Python are not covered by the same check

The `ruby` and `python` entries in `mise.toml` are deliberately not covered.
Ruby is pinned by `.ruby-version` and read by rbenv, which is a separate
arrangement with its own history (the CI runner carries an `RBENV_VERSION`
that outranks the file); Python has no second file to disagree with.

## Why every workflow reads a pin file instead of writing the version inline

A workflow that writes the version inline is invisible to a pin-agreement
check, which is how the mobile lane sat on major 22 unnoticed.
`spec/config/node_version_pin_spec.rb` also asserts no `.github/workflows/*.yml`
file writes `node-version:` inline — every workflow has to read one of the
pin files, so there is nothing to keep in step by hand.
