---
lat:
  mode: explanation
---

# Why Sway::Release reads git the way it does

`Sway::Release` (`lib/sway/release.rb`) falls back to a live `git` read in development when `SWAY_RELEASE_SHA` is unset (see `docs/reference/release-metadata-values.md` for the full value table).

This document covers why that fallback is bounded, uncached, and deliberately absent from one reader.

## Why GIT_TIMEOUT_SECONDS is 10

Reading HEAD out of a repository from a healthy local repository is instant; the bound exists for the case where it is not.

Reading HEAD out of a repository from a healthy local repository is instant; the bound exists for the case where it is not — a `.git` on a network volume that has stopped answering, an index lock somebody left behind, a credential helper that decides to prompt. `Open3.capture2` waits for any of those forever, and this runs inside a request that renders the footer. Ten seconds is far above a healthy read and far below anything a reader would sit through.

## Why sha is not memoized

Rails' development reloader only re-evaluates a file when its mtime changes, and `git commit` does not touch the timestamp of any already-saved file.

Rails' development reloader only re-evaluates a file when its mtime changes, and `git commit` does not touch the timestamp of any already-saved file — so a value cached for the life of the process would keep reporting the pre-commit sha after every later commit. This page exists to say truthfully what is running, so each render reads git again; the small cost per development render is accepted.

## Why built_from_committed_tree? never falls back to git

Unlike `sha`, `built_from_committed_tree?` reads `SWAY_UNCOMMITTED_DIGEST` from `ENV` directly and never falls back to a live git read.

That fallback only ever ran in development, and cost a git subprocess per page — this method rides on every response, unlike the release-footer-only `sha` read.

Reading `ENV` directly (rather than a settings wrapper with a default) matters here because empty and absent mean different things: a deploy always sets `SWAY_UNCOMMITTED_DIGEST`, empty for a clean tree and non-empty for an uncommitted change, so an absent value means no deploy set it at all. `built_from_committed_tree?` returns `true` for exactly the clean-tree case, `false` when the tree carried more, and `nil` when nobody recorded the value in the first place.

## Why to_sway_json reads sha once

`to_sway_json` reads `sha` once and derives `short_sha` from it, rather than calling the public `sha` and `short_sha` readers separately.

`to_sway_json` reads `sha` once and derives `short_sha` from it, rather than calling the public `sha` and `short_sha` readers separately — `short_sha` itself calls `sha` again, so that would run the dev-only git fallback twice per render.

`spec/lib/sway/release_spec.rb`'s "subprocess count for the git fallback" examples assert on the number of real `git rev-parse HEAD` subprocess calls, not on the returned value, because a regression back to calling `sha` twice returns the same value either way — counting subprocess calls is the only way this fails on that regression.

## Why config/deploy.yml's release build args are wrapped in single quotes

`config/deploy.yml`'s release-tracking build args (`SWAY_RELEASE_VERSION`, `SWAY_RELEASE_SHA`, `SWAY_PREVIOUS_SHA`, `SWAY_DEPLOYED_AT`) must still be plain strings after both ERB and YAML have run over the file.

Left unquoted, YAML coerces the ISO-8601 value of `SWAY_DEPLOYED_AT` into a Ruby `Time`, which `Time.iso8601` can no longer parse — the page then shows the deploy date as `"—"` — and coerces an empty `SWAY_PREVIOUS_SHA` into `nil`. Wrapping the ERB output in single quotes in the YAML keeps all four values as strings regardless of what they look like. `spec/config/deploy_release_args_spec.rb` renders the file with ERB values stubbed and checks all four come back as strings.

## Why the uncommitted-changes digest is checked at every link of its chain

`SWAY_UNCOMMITTED_DIGEST` travels `scripts/deploy.sh` -> `builder.args` in `config/deploy.yml` -> a Dockerfile `ARG` -> an `ENV` -> `Sway::Release` (see `built_from_committed_tree?` above).

Breaking any one link makes `/version` report "built from exactly the commit above" forever — the confident wrong answer this whole mechanism exists to prevent — and nothing else would notice: the deploy still succeeds and the page still renders. The spec checks the Dockerfile link by POSITION, not just presence: a declaration in an earlier build stage is thrown away by Docker, and an earlier version of this check could not tell the two apart, so it scans only the text after the last `FROM` line (the runtime stage). The value itself can only be computed where `.git` is — the host, before the build, never inside the image — so what `scripts/deploy.sh` does with it is checked separately, by running the script, in `spec/config/uncommitted_digest_spec.rb`.

## Why Version.tsx's "Built from" cell says what it says

`/version` — details about the build that is running.

The same data reaches every page and feeds the logo tooltip; this page is the address you can link to, and the way to read it on a touch device where there is no hover. It is public on purpose: a civic project should be open about what it is running.

A commit id alone answers "what is running" only when the build came from that commit and nothing else. A release can ship uncommitted changes, and a page that reported only the bare commit would present it as though it were the whole answer.

When `built_from_committed_tree` is `undefined` — only a deploy records this — the page shows "not recorded — this build did not come from a deploy" rather than "exactly the commit above": saying "exactly the commit above" here would be a confident lie while the tree is being edited.

## ReleaseInfo.tsx, the logo tooltip

`ReleaseInfo` wraps the Sway logo — hovering (or focusing, if the child is a link) reveals the running build.

SHAs render as selectable monospace text so they can be copied. The dedicated `/version` page (linked from the footer) covers touch devices with a permanent link, since hover tooltips do not work on touch screens.

This tooltip is on every screen while `/version` is one link in the footer, so it is the more visible place to answer confidently and wrongly.

`ReleaseInfo.test.tsx` exists because this component has three answers for "Built from" (exactly that commit, that commit plus uncommitted changes, or not recorded), and reading the missing one as "yes" would claim a clean tree while the tree is being edited. Nothing covered this component before. Its tests use the house pattern for a Radix tooltip: the real one renders its content into a portal only once open, so a test could never read it otherwise.

## Why release is a shared Inertia prop

`ApplicationController` ships `Sway::Release.to_sway_json` as a shared `inertia_share` prop (`release:`) on every page.

`ApplicationController` ships `Sway::Release.to_sway_json` as a shared `inertia_share` prop (`release:`) on every page, rather than loading it only where the logo tooltip lives, so the tooltip can show the running build's metadata anywhere in the app. The value is constant for the life of the process — in production it comes from plain `ENV` reads with no git calls, per the per-environment behavior above — so recomputing it on every request costs nothing beyond the reads already described here.
