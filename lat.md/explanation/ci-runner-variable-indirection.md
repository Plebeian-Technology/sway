---
lat:
  mode: explanation
---

# Why no workflow names the machine it runs on

A GitHub Actions workflow must not name the machine it runs on directly.

Each job reads a `CI_RUNNER` repository variable, set only where a particular machine is genuinely wanted, and falls back to a GitHub-hosted runner (`ubuntu-latest`) everywhere else — including a fresh clone and any fork.

Writing a machine into the workflow file instead does two bad things at once: it tells every reader something about the setup that runs this project, and it sends jobs to a runner a reader's own copy does not have, where they wait forever. `mobile-test` also runs on `pull_request`, so a hardcoded self-hosted runner there would run a stranger's test files on that machine.

## Why the fallback matters as much as the indirection

The fallback to a hosted runner is the half that actually matters.

A job whose runner comes only from a variable, with no fallback, runs nowhere at all once that variable is unset — which is exactly what every fresh clone and every fork looks like. `spec/config/ci_runner_selection_spec.rb` checks both halves: that no workflow names a `self-hosted` runner outright, and that every `vars.CI_RUNNER`-style read is paired with a hosted fallback (`ubuntu-`) rather than left to queue forever with no machine willing to take it.
