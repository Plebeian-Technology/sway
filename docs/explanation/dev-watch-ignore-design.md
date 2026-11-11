---
mode: explanation
summary: "Why devWatchIgnore's test coverage checks both directions of the ignore decision, and the worktree coverage-report case that started it."
status: agent-extracted
related: [docs/explanation/dev-reload-reason-diagnostic.md]
---

# Why `devWatchIgnore` is tested in both directions

This decides what the dev server ignores, and it has to be wrong
in only one direction to be useless: ignore too much and editing a template
stops reloading the page, with no error to say so. So both directions are
checked here, and the file that started it — a coverage report written by a
test run in an agent's worktree — has an example of its own.
