---
mode: explanation
summary: "Why Sway::Utf8.scrub exists, and why String#encode cannot replace it for cleaning up bytes tagged UTF-8 that are not valid UTF-8."
status: agent-extracted
related: []
---

<!-- vale Vale.Spelling = NO -->

# Why Sway::Utf8.scrub exists

`Sway::Utf8` is one place to turn bytes-from-the-outside into a string
Ruby's regexp engine will accept.

Text that reaches Sway from a subprocess (`mutool draw -F txt`), a file on
the storage volume, or a column written by an older build can be arbitrary
bytes tagged UTF-8. Every regexp operation on such a string raises — `gsub`
and `match?` raise `ArgumentError`, `strip` raises
`Encoding::CompatibilityError` — and those raises surface far from the read,
inside rescue ladders written for entirely different failures.

## Why scrub is lossy only where necessary

`Sway::Utf8.scrub` is lossy only where the input was already unreadable:
every valid byte sequence survives untouched, and only the invalid bytes
are replaced. That is what keeps an attachment usable rather than dropped
wholesale — a document with one bad byte still reads, instead of being
discarded because a single byte could not round-trip.

## Why String#encode does not work here

`String#encode("UTF-8", invalid: :replace)` looks like the obvious fix, but
it does not work: encoding a UTF-8 string to UTF-8 is a documented no-op and
leaves the invalid bytes in place. `String#scrub` is the operation that
actually replaces them, which is what `Sway::Utf8.scrub` calls.
