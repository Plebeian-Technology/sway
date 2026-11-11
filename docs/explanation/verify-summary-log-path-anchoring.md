---
mode: explanation
summary: "Why verify-summary.mjs became its own spec-tested script instead of a node -e string inside verify.sh, and why its log column must be an absolute path."
status: agent-extracted
related: []
---

# Why the verify-run summary is its own tested script

`summary.json` is what every later reader of a `dip run verify` run is
told: which lanes ran, which state each reached, and which examples
failed. It used to be built by a `node -e` string inside
`scripts/dip/verify.sh`, where no linter could see it and nothing could run
it against a known input. `scripts/dip/verify-summary.mjs` is the
extracted, spec-tested replacement; `spec/scripts/verify_summary_spec.rb`
runs it over a planted facts file and log fixtures.

## Why the log column has to be an absolute path

The log column is anchored to the spec's own temp directory. `verify.sh`
writes a path relative to the repo root and runs node from there; left
relative in a spec running from a different working directory, node would
resolve it against the repo root too, find nothing, and every
`failing_examples` assertion would pass by reading an empty list — which is
exactly what happened when this was first written.
