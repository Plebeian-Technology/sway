---
lat:
  mode: explanation
---

# Why GitHubPrService is built the way it is

`GitHubPrService` opens ONE combined GitHub pull request per `RefreshLegislatorsCacheJob` run, holding every locale JSON file that changed.

It uses Octokit, GitHub's own Ruby library — NOT the `gh` command line tool, which is installed neither in the repo nor on the production Raspberry Pi. The library is `github.com/octokit/octokit.rb`, already referenced in `.kamal/hooks/pre-deploy.sample`.

## Security notes

Security constraints governing GitHub token handling, whitespace sanitization, and automated pull request generation.

- `GITHUB_TOKEN` comes from `EnvSecret.fetch!`, which trims the trailing
  newline `kamal env push` leaves on a secret read from a file, and raises
  a `KeyError` on a blank value rather than trying to authenticate with
  `" "`. The token is NEVER handed to any logger.
- The token is a fine-grained personal access token, allowed to write
  contents and pull requests on the Sway repo ONLY (see
  `docs/kamal-secrets.md`).
- The branch name is built from `Date.current.strftime`, so nothing a user
  typed reaches it.

## What open_pr(branch:, title:, body:, files:) promises

Contractual guarantees provided by the PR service, including base tree derivation, fast-exit on empty inputs, and branch commit safety.

- Returns `nil` straight away when `files` is empty, without calling the
  API at all.
- Otherwise it starts the branch from the tree of the newest commit on the
  default branch (`base_tree` must be a TREE id, NOT a commit id), commits
  each file in turn through blob → tree → commit → update_ref, then opens
  ONE pull request.
- If the branch name is already taken, which happens when the job runs
  twice in one day, it logs a warning and re-raises so
  `RefreshLegislatorsCacheJob` reports the error to Sentry.
- If GitHub rate-limits it: logs, reports to Sentry, re-raises.

## Why GIT_TIMEOUT_SECONDS exists

The one local `git` read (`repo_from_git_remote`) used to be a backtick, which runs a shell and waits for it forever.

The one local `git` read (`repo_from_git_remote`) used to be a backtick, which runs a shell and waits for it forever — so a `.git` that has stopped answering (a network volume, a leftover index lock, a credential helper that decides to prompt) hung the job thread with nothing watching the clock. Nothing here is attacker-shaped: the argument list is fixed. The bound is about the wait, not the words.

## Why GITHUB_REPO is read with EnvSecret.read, not ENV.fetch with a block

`@repo` looks for the `"owner/repo"` name in the environment first.

Production needs that, because the Docker image leaves `.git/` out through `.dockerignore`, so `git config` returns `""` inside the container. Local development falls back to the git remote. `FetchLawCorpusService` handles `LAW_XML_GITHUB_REPO` the same way.

It is read through `EnvSecret` rather than `ENV.fetch(name) { block }`. The block form only runs when the variable is ABSENT, so it caught neither bad shape: `""` was accepted as a repo name, and `"owner/repo\n"` survived into Octokit's URL building as `repos/owner/repo%0A` — a 404 that looks just like a deleted repository. `EnvSecret.read` returns `nil` for both, which is what makes the `||` fallback to `repo_from_git_remote` reachable.

## Why base_tree must be a tree id, not a commit id

`base_tree` wants the id of a TREE, not of a commit. GitHub's `create_tree` insists on a tree id; hand it a commit id and it quietly drops the content of the files that were already there.

## Why create_blob's return value is read as blob.sha, not .sha directly

`create_blob` returns the id as text, not an object holding it — its own last line is `blob.sha`. Asking text for `.sha` raised weekly, after the branch was made and before any file landed.

## Why the rate-limit rescue is safe to log in full

On `Octokit::TooManyRequests`, the token value NEVER reaches the log or the Sentry report.

On `Octokit::TooManyRequests`, the token value NEVER reaches the log or the Sentry report: Octokit's rate-limit errors carry only the URL and "API rate limit exceeded", never `GITHUB_TOKEN`, so dumping the message and backtrace is safe.

## Why current_commit_sha and base_tree_sha are reassigned after every file

Inside the `files.each` loop, both `current_commit_sha` and `base_tree_sha` are moved forward to the commit and tree just created, before the next file is committed.

That is what lets one pull request end up holding all of them: each file's commit builds on the previous file's tree rather than starting over from the branch's original base.

## Why default_branch is memoized

`#default_branch` remembers the default branch name so the service only asks GitHub for it once per run.

## Why repo_from_git_remote is production's fallback, never its primary path

`repo_from_git_remote` is the local-development fallback when `GITHUB_REPO` is not set. Production cannot use it: the Docker image leaves `.git/` out through `.dockerignore`, so `git config` returns `""` there.
