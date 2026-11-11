---
mode: explanation
summary: "Explains why SWAY_RELEASE_SHA must be declared in both the frontend build stage and the final stage of the production Dockerfile, and what silently breaks if the build-stage copy is missing."
status: agent-extracted
related: [release-metadata-values]
---

<!-- vale Vale.Spelling = NO -->

# Why SWAY_RELEASE_SHA is declared twice in the Dockerfile

The commit a build came from has to be handed to the frontend build, and
only the Dockerfile can do it.

`vite.config.ts` reads `SWAY_RELEASE_SHA` and sends it to Sentry as the name
for this build's source maps. A Docker build stage cannot see values
declared in a later stage, so the name has to be declared a second time in
the stage that builds the frontend. The final stage already declares it for
a different reader (`Sway::Release`, at runtime), and that one is easy to
mistake for enough.

## What breaks if it goes missing is quiet

The upload still works, and the maps still match the code — Sentry pairs
them by an id stamped into both files, not by the name — so nothing fails
and no error is logged. Every build is simply filed under the word
"undefined" again, and the Source Maps page stops being readable. That is a
fault nobody notices until they need it.

`spec/config/sentry_release_name_spec.rb` checks that the frontend build
stage of `docker/dockerfiles/production.alpine.dockerfile` declares
`SWAY_RELEASE_SHA`, and that `vite.config.ts` and
`vite/sentryReleaseName.ts` both read that same setting name.

## Why the frontend build stage's end marker is the whole command, not just the task name

The spec's `#frontend_build_stage` extracts everything from the start of
the `FROM gems AS build` stage up to the FULL
`./bin/rails assets:precompile` command, not just up to the task name
`assets:precompile`. Two comments further up the Dockerfile name that task
in prose, and stopping the region at the first occurrence of the bare task
name cut the extracted region short there instead — which made the check
fail against a Dockerfile that was actually correct.

## Why `sentryReleaseName.test.ts` cares most about the no-value case

`vite.config.ts` sends this to Sentry as the name for a build's source maps.

The interesting half is what happens with NO value. A wrong name is worse
than no name: it files one machine's maps under another build, and the two
then look identical in Sentry. So every empty shape must come back undefined,
and `vite.config.ts` leaves the option out entirely when it does.
