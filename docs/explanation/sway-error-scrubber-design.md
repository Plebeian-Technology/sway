---
mode: explanation
summary: "Why SwayErrorScrubber exists, why its rules table lives under app/frontend, and specific defects it has already caught."
status: agent-extracted
related: [docs/explanation/error-scrubber-empty-fingerprint-bug.md, docs/explanation/fake-error-collector-design.md]
---

<!-- vale Vale.Spelling = NO -->

# SwayErrorScrubber design notes

`SwayErrorScrubber` (`lib/sway_error_scrubber.rb`) strips personal
data from an error before it is sent.

## Why the scrubber exists

The local collector scrubs nothing and keeps everything, and public testimony
text can contain home addresses and e-mail addresses; that text reaches error
payloads and model prompts, so the collector must scrub.

`SwayErrorScrubber` is a second layer only. The first is that the SDK sends
no request bodies, no headers, and no local variables. See the spec for what
a pattern cannot find.

## Why the rules table has three readers

`RULES_PATH` (`app/frontend/sway_constants/errorScrubRules.json`) is one
table with three readers: this scrubber, the web scrubber, and the mobile
one. Three copies can drift — Ruby dropped a key
named "secret" and neither JavaScript reader did, so that value left the
browser and the phone and not the server. Nobody chose that; it sits under
`app/frontend` because Metro already watches that directory, which is how
the mobile app reaches shared constants.

## Why the production image must not delete `RULES_PATH`

The production image throws away `app/frontend` once the frontend assets
are built, since none of it is needed to serve the compiled bundle. `lib/`
is in Rails' eager-load paths, though, so production loads every file
under it while starting — including `lib/sway_error_scrubber.rb`, which
reads `RULES_PATH` (`app/frontend/sway_constants/errorScrubRules.json`) as
it loads.

If the image's cleanup step deleted the whole `app/frontend` directory,
that read would raise `Errno::ENOENT` and the container would die on its very
first command, with nothing pointing at the missing file.
Nothing else could have caught it beforehand: dev, test, and CI all keep
the file on disk, so the read only fails inside the built image, once
`app/frontend` has actually been pruned. `spec/config/production_image_files_spec.rb`
scans shipped Ruby (`lib/`, `app/`, `config/`) for every string literal
that names an `app/frontend` path, and checks the Dockerfile's `find`
prune step preserves each one by name — so a new load-time read from
`app/frontend` fails this spec instead of failing a live deploy.

## Why `.dropped` preserves type

Sentry's protocol declares `request.headers` and `request.cookies` as maps,
and a string there is invalid. The collector accepts one, but Android's
native SDK casts the field and throws while reading the envelope, losing
the whole error with nothing said in the app. Observed on an Android
emulator; the sibling scrubber in
`mobile/src/observability/scrub_error_event.ts` carries the stack trace.

The measurement, from `scrub_error_event.ts`'s own comment:

```
java.lang.ClassCastException: java.lang.String cannot be cast to java.util.Map
    at io.sentry.protocol.Request$Deserializer.deserialize
```

It throws while reading the envelope and the whole error is lost, with
nothing said in the app. Observed on an Android emulator: the address
was right, the collector was reachable, a session envelope went through,
and the error never arrived. iOS accepts the string, which is why this
survived a passing simulator test.

## Why `dropped()` preserves type in `scrub_error_event.ts`

`app/frontend/sway_utils/scrub_error_event.ts` states the same rule in its
own words: dropping a value must not change its TYPE. Sentry's protocol
declares `request.headers` and `request.cookies` as maps, and a string there
is invalid. The browser's collector accepts it, but Android's native SDK
casts the field and throws, losing the whole error with nothing said in the
app. Same scrubber shape, so the same rule here — see the sibling in
`mobile/src/observability/scrub_error_event.ts` for the measurement.

## Why breadcrumbs need their own scrub

`sentry-rails` subscribes to ActiveSupport notifications, and its
allowed-key list for `start_processing.action_controller` includes
`:params`. Those are `request.filtered_parameters`, and
`filter_parameter_logging.rb` does NOT filter street, city, postal_code,
latitude or longitude — exactly what the registration form posts, so a
breadcrumb can carry a home address without `.scrub_breadcrumbs`.

## Why one spec detects a pasted list, not just a missing table reference

`spec/lib/error_scrub_rules_shared_spec.rb` guards against the failure that
actually reintroduces drift: someone adds a rule by pasting the
`droppedKeys`/`preservedKeys` list back into one scrubber file directly. It
reads as a local tidy-up, but it puts the three-copies drift (above) right
back.

The example counts values found on ONE LINE, because a pasted list is a
line holding several values at once and prose is not. It deliberately
stays below that count when a single key is named on its own — in a
comment, or a field access like `request.cookies` — so the check does not
fire on ordinary correct code that happens to mention one rule's name.

## Why a dropped `request.headers` map must stay a map

Sentry's protocol declares `request.headers` a map. A string there is
invalid, and Android's native SDK throws on it and loses the whole
error on an Android emulator. The browser's collector
is more forgiving, but the shape has to be right in all three
scrubbers or only one platform ever tells you.

## Why `scrubString` (mobile) caps a huge value before redacting, not after

`mobile/src/observability/scrub_error_event.ts`'s email pattern is
quadratic, so redacting before capping took seconds on a long string.
Capping first holds every pattern to ~2KB, which is what
`mobile/__tests__/observability/scrub-error-event.test.ts` stays fast
against.

## Why `event_id`, `trace_id`, `span_id`, `parent_span_id`, and `timestamp` are left untouched

A rewritten `event_id` is not valid, so the collector drops the whole
envelope and the error is lost with no message. `scrubErrorEvent`
(mobile) leaves this small set of fields alone for that reason, rather
than walking them like the rest of the event.

## Why the mobile breadcrumb hook drops push-token entries

Sentry keeps a trail of recent activity — "breadcrumbs" — alongside every
error report. `mobile/src/observability/sentry.ts`'s `beforeBreadcrumb`
hook (`scrubPushTokenBreadcrumb`) throws away any entry whose data
mentions `getDevicePushTokenAsync`, and any entry whose request URL
points at the device push-token endpoint. That keeps push tokens out of
error reports sent from the app; on the Rails side, `filter_parameters`
does the same job.

## Why the backtracking guard allows two seconds

`scrub-error-event.test.ts` scrubs a 55,000-character string and asserts the
call returns inside a fixed wall-clock bound. The bound started at 250ms and
went red at 294ms during a `dip run verify` run, where fourteen lanes compete
for the same cores.

A wall-clock assertion on a busy machine measures the machine as much as the
code, so the question is what margin the guard actually needs. What it exists
to catch is catastrophic regex backtracking, which is not an 18% overrun — it
is orders of magnitude, taking a string like this one from milliseconds to
many seconds or to no answer at all. Two seconds sits well clear of anything
contention can produce on this input while still separating cleanly from a
blowup, so the guard keeps its meaning without depending on what else the
machine happens to be doing. The web scrubber's `scrubErrorEvent.test.ts`
carries the same guard on the same input and went red the same way under the
same contention, so it takes the same two-second bound for the same reason.
