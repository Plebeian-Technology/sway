---
mode: explanation
summary: "Explains why SwayErrorScrubber sets a truthy empty fingerprint to nil instead of leaving it as an empty list."
status: agent-extracted
related: []
---

<!-- vale Vale.Spelling = NO -->

# Why the error scrubber clears an empty fingerprint

Every event `sentry-ruby` builds carries `fingerprint = []` from the moment
it is constructed (`event.rb` sets it in `initialize`). An empty array is
truthy in Ruby, so any code that only checked whether a fingerprint was
present treated it as one the app had deliberately chosen.

That distinction matters to the collector receiving the event. It reads a
present fingerprint — even an empty one — as "the app chose this grouping
key," not "the app chose none," and groups every event carrying it into a
single issue. Left alone, every scrubbed error in the whole app would land
in one bucket instead of being grouped by its own stack trace.

Setting the field to `nil` instead of `[]` fixes this, because the
serializer skips falsey values when building the outgoing payload — `nil`
drops the `fingerprint` key entirely, and the collector falls back to its
normal per-error grouping.

## How this was found

Found by the first run of the wire check — the only
tool in this codebase that reads the event as it is actually sent over the
wire, rather than the in-memory object before serialization. It resolved an
earlier puzzle: six mobile errors had been appearing grouped inside one
unrelated Ruby issue. The mobile scrubber (`scrub_error_event.ts`) had
already been fixed to clear its own empty fingerprint; the Ruby half had
not, because nothing had inspected the actual wire format to notice the gap.

## Why `scrubErrorEvent` (the web `beforeSend` hook) also removes it

`app/frontend/sway_utils/scrub_error_event.ts`'s `beforeSend` hook walks the
whole event, so it also covers fields no code there names. It never returns
null: the aim is a report safe to keep, not no report.

It also removes an EMPTY fingerprint. The collector reads `"fingerprint": []`
as "the app chose a fingerprint" rather than "chose none", so every error
collapses into one issue. This browser SDK is not known to send it — Ruby and
Android both do — but the three scrubbers drift apart when a rule lands in
only one of them, and that has already cost real errors.

## Why `mobile/__tests__/observability/scrub-error-event.test.ts` calls this Android-only

Only Android sends an empty fingerprint. The collector reads an empty list
the same way there as everywhere else — "the app chose a fingerprint" —
so every Android error collapsed into one unrelated issue before mobile's
`scrubErrorEvent` removed it. Measured on an emulator.

`scrubErrorEvent`'s own comment names the specific collapse this fixed:
ours landed under a Ruby error titled "fresh clone probe", six of them,
while the screen said nothing had arrived. iOS omits the key and groups
correctly.
