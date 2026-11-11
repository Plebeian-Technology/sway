---
mode: explanation
summary: "Explains why the source-map upload decision and delete decision are each made independently in two different files, and why the secrets they read must be exported rather than bare shell assignments."
status: agent-extracted
related: [sentry-release-name-dockerfile-duplication]
---

<!-- vale Vale.Spelling = NO -->

# Why source-map upload and deletion are checked against each other

One decision, written in two places.

The frontend build writes a `.map` file beside every `.js` file it emits.
Those maps turn an unreadable stack trace from a browser back into real file
names and line numbers. Sentry needs them; a visitor does not, and they are
15 MB.

So the production image uploads them and then deletes them. Two different
files decide the two halves:

- `vite.config.ts` decides whether to UPLOAD, by testing three environment
  variables (`SENTRY_AUTH_TOKEN`, `SENTRY_ORG`, `SENTRY_PROJECT`).
- The production Dockerfile decides whether to DELETE, by testing the same
  three in a shell.

When those two conditions drift apart, the gap between them is a build that
deletes the maps after uploading nothing — and nobody finds out until an
error arrives with no readable frames, during an outage. Testing only
`SENTRY_AUTH_TOKEN` in the shell used to leave exactly that gap.

`spec/config/sentry_sourcemap_guard_spec.rb` keeps the two lists identical.
It reads the real files rather than a copy of the names, so a rename in
either file fails here.

## Why the secrets the asset build reads must be exported

Both conditions above can name every variable and still upload nothing.
Only an EXPORTED shell value reaches a child process, and vite is a child,
so a bare assignment leaves the token unreadable to the plugin while every
other check here stays green. That was the original fault.

The check is scoped to the asset-build block ON PURPOSE: the bundle-install
block in the same Dockerfile reads the same token with a deliberate bare
assignment, because exporting there would hand a credential to every gem's
build script. A rule over the whole file would fail on correct code.

## Why the source-map upload retries on failure

`vite.config.ts` wraps the Sentry plugin's source-map upload so a failed upload
is tried again before the build gives up. A deploy can be lost to
one name lookup that does not answer.

Two halves are checked in `sentryUploadRetry.test.ts`. The first is that the
wrapper does what it says. The second is that the plugin still has the shape
the wrapper needs — that half is somebody else's code and is free to change on
any version bump, and if it changes the wrapper returns the plugin untouched
and the retries stop happening with nothing to show for it.
