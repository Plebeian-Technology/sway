# Browser error reporting

The JavaScript bundle reports errors to Sentry only when the build that made it carried a DSN, and the DSN reaches the build as a secret rather than as a value in the tree.

## An omitted message must not create a second event

The shared error-helper omits captureMessage when the caller supplied no message. The exception report remains the evidence for the failure.

`handleError` previously reported its empty default message before reporting the
exception. An upload failure therefore created an unlabeled event as well as
the useful exception. Guarding `captureMessage` with `message?.trim()` ensures
only the exception is sent when no message is provided, while explicit messages,
exception reporting, and the cancellation response retain their separate contracts.

## Why the browser DSN is a build secret

Vite fixes environment values into the bundle while it builds, so a DSN supplied at container start arrives too late and the browser never reports anything.

`VITE_SENTRY_DSN` is therefore listed under `builder.secrets` in `config/deploy.yml`, mounted by the Dockerfile for the one build step that runs Vite, and exported inside that step; a plain shell assignment would not reach the child process. `app/frontend/sway_utils/sentry.ts` starts Sentry only in production mode and only when the bundle carries the value.

The value is absent on purpose from every build that is not a real deploy. `dip preview` and a laptop `pnpm build` both build "the production way" without being production, so build mode alone cannot say whether a bundle should report, and `scripts/dip/preview.sh` passes no Sentry secrets. A preview that reported would arrive in Sentry looking exactly like the live site.

`SENTRY_ORG` and `SENTRY_PROJECT` travel the same route so the build can upload source maps, and the Dockerfile deletes the maps from the image only when all three of token, org and project were present, the same three `vite.config.ts` tests before uploading (`spec/config/sentry_sourcemap_guard_spec.rb` holds the two lists together).

## A trailing newline in a DSN turns reporting off without saying so

The DSN is parsed as a URI, so a value carrying a trailing newline fails that parse and the client disables itself silently.

Nothing announces it: the application starts, serves pages and reports nothing,
which is indistinguishable from a quiet week. The value is therefore stripped
before it is parsed, and that stripping is pinned as behaviour rather than left
as a habit — the same failure shape as a credential
[[outbound-email#A trailing newline reads as a revoked key|read as revoked]]
because of one invisible character.

## Development reports stay on this machine

Outside production the browser sends its errors to a collector running locally
rather than to the hosted service.

Recognising a local collector address is what keeps a developer's stack traces,
and whatever a page happened to be holding, off a third party. The recogniser's
negative cases carry the weight: reading a hosted address as local would send
nothing anywhere, while reading a local address as hosted is the leak.

An error boundary outside production reports the failure but skips the storage
and cache resets it performs for a reader, because clearing state under
somebody who is working on the application destroys the thing they were
inspecting.

The scrubber that strips private values from an event is checked against
planted values — every value in its test invented rather than borrowed — so
the test itself never becomes the leak it guards against.

### Where each development address is read

The collector's address is read in three places, and which place a value belongs
to follows from which process needs it.

The web and test containers get theirs from the dip scripts, because those
processes run under dip. The mobile app does not: Expo runs on the host, so its
address is read by the tool environment the host shell already loads, and the
stored value names localhost while the app rewrites it for the Android emulator,
which reaches its host under a different address. The editor's own integration
reads a third value the same way.

Every one of them is a per-machine file that git ignores, so no tracked file
holds a token or an address, and every one of them resolves to empty when the
file is absent. Empty is the wanted answer for a fresh clone: the browser and
Ruby clients simply stay off, and the editor integration exits and reports
itself as failed, which is visible rather than silent.

### One rule table, three readers

The redaction rules live in one JSON table read by the web scrubber, the mobile
scrubber and the Ruby one, rather than as three lists.

They were three copies once, and they drifted: the Ruby copy dropped a key
named "secret" that neither JavaScript copy dropped, so the same event was
scrubbed differently depending on which process reported it. The table stores
each pattern as source text and each language compiles it with its own flags,
which is the one thing that cannot be shared.

## The cache trap when toggling a build secret

Docker keeps secret values out of what it uses to decide whether a step can be reused, so adding or removing a build secret and changing nothing else reuses the previous build and the switch appears to do nothing.

The first test of the reporting switch said "off" in both directions for this reason, and the test was wrong rather than the code. Changing a file as well, or passing `--no-cache-filter=build`, forces the step to run.

## Console error forwarding guards against empty exceptions

Overriding console error in production filters empty arguments and routes non-Error values to message capture instead of synthetic exceptions.

When code or browser extensions invoke `console.error(null)` or `console.error(undefined)`, blind forwarding to `Sentry.captureException` generates events titled `Error: undefined` with no stack trace. In [[app/frontend/sway_utils/sentry.ts#SentryUtil]], `window.console.error` inspects arguments, ignoring falsey values, forwarding Error instances to `captureException`, and capturing formatted non-Error arguments through `captureMessage`. Sentry's `beforeSend` drops any event lacking stack frames whose message is `"undefined"`, `"null"`, or empty.
