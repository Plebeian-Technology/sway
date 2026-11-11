---
mode: explanation
summary: "Explains why Sway::Subprocess caps stdout and stderr in size, why OutputTooLarge carries stderr, and how the two output pipes are drained concurrently without deadlock."
status: agent-extracted
related: ["docs/explanation/subprocess-bounded-execution.md", "docs/explanation/subprocess-deadline-design.md", "docs/explanation/subprocess-termination-and-pid-reuse.md"]
---

# Why Sway::Subprocess caps stdout and stderr

<!-- vale Vale.Spelling = NO -->

`Sway::Subprocess.capture3` (`lib/sway/subprocess.rb`) does not just bound
how long a child process may run — it also bounds how much it may write.
This document explains why those caps exist, why `OutputTooLarge` carries
stderr instead of discarding it, and how the two output pipes are drained
without deadlocking each other.

## Why output needs a cap at all

The deadline in `docs/explanation/subprocess-deadline-design.md` bounds how
long a child may run. It does nothing about how much it writes. The reader
threads used to be plain `Thread.new { io.read }`, which reads to
end-of-file into a Ruby String with no cap and nothing discarded along the
way.

Every other size control in this subsystem sits downstream of that
buffer — none of them limit what `capture3` itself holds in memory:

- `MAX_ATTACHMENT_TEXT_CHARS` trims the string the extractor has already
  returned.
- `Sway::Utf8.scrub(stderr)[0, 500]` trims the message after cleaning the
  whole buffer.
- `Legistar::AttachmentFetch::MAX_ATTACHMENT_BYTES` limits the PDF as it
  comes off the wire, not what `mutool` expands it into.

`MAX_STDOUT_BYTES` is 16 MiB. That is far beyond any genuine testimony
document — across a sweep of 797 attachments, the largest extracted text
layer was orders of magnitude smaller — and still small enough to hold
twice over on the Pi, which matters because
`FetchHearingsService#attempt_extraction` retries once.

`MAX_STDERR_BYTES` is 256 KiB. stderr is diagnostics, and every caller
trims the message to 500 characters anyway, so this cap is three orders of
magnitude larger than anything downstream can use. No attacker is needed to
reach it: `mutool` prints one `error:`/`warning:` line per malformed
object, so a scan submitted by the public with a damaged cross-reference
table produces diagnostics in proportion to how many objects it holds.

`CHUNK_BYTES` (64 KiB) is the read granularity. The overflow check runs
after each chunk is appended rather than before, so the peak buffer for a
stream is its cap plus at most one chunk. That is the price of not
misreporting a stream that lands exactly on the cap as an overflow (see
"How `.drain` decides a stream overflowed," below).

## Why OutputTooLarge carries stderr

`OutputTooLarge` is a sibling of `TimedOut` in every way that matters: a
plain `StandardError`, deliberately not a `SystemCallError`, and each
caller turns it into its own kind of failure — so an over-large extraction
stays a failure of that one attachment, with a visible reason on the
mirror, instead of the process running out of memory.

Unlike `TimedOut`, it also carries the bounded stderr, because raising
instead of returning would otherwise take that whole stream away from the
caller — and one caller reads it to detect a specific kind of failure.
`MupdfExtractor` decides whether `mutool` was built without bundled OCR by
looking for `"OCR Disabled in this build"` in stderr. `mutool` prints one
warning line per malformed object while parsing, and parsing happens before
the draw step that prints that message, so a malformed scan submitted by
the public can push the telltale line past the cap.

Losing that line costs the whole run. The answer is remembered per worker,
so without it, every image-only bill would retry the same doomed attempt
until the consecutive-failure budget fails the run outright.

`OutputTooLarge#stderr` is always a String, never nil, so a caller does not
have to tell "there was no stderr" apart from "this exception predates the
field."

## Why the two pipes are drained concurrently

`.drain_within` reads stdout and stderr on separate threads at the same
time. A child that fills the stderr pipe buffer blocks on write while the
caller is blocked reading stdout — a deadlock the deadline would then have
to resolve on its own, at the cost of the full timeout.

Each reader stops at its own cap and kills the process group on the way
out. Stopping alone is not enough: the child would then block forever
writing into a full pipe, the caller would wait out the whole deadline, and
would then be told the wrong thing (`TimedOut` rather than
`OutputTooLarge`). Killing the process group from inside the reader makes
`wait_thr` return promptly, so a size problem is reported on a size
problem's own timescale instead of the deadline's.

## How `.drain` decides a stream overflowed

`.drain` reads one pipe to end-of-file or to its limit, whichever comes
first. The overflow test runs after the chunk is appended, so a stream that
lands exactly on the cap is returned intact rather than reported as an
overflow. The peak buffer size is therefore `limit + CHUNK_BYTES` — the
price of that distinction, and it stays bounded.

`.drain` rescues `IOError` because the caller's timeout path kills these
reader threads and closes the pipes out from under them. Whatever was read
so far is a better answer than an exception raised inside a thread that is
already being torn down.

The rescue is scoped to the LOOP inside `.drain` rather than to the whole
method body, so both locals (`buffer`, `overflowed`) are unconditionally
assigned before anything can raise and the method has exactly one exit. As a
method-level rescue, steep read `overflowed` as `nil | bool` on the
`IOError` path — correctly, since the rescue can be reached from a state
where the assignment above has not run.

## Why `.reencode` puts the external encoding back

`IO#read(length)` hands back raw bytes (`ASCII-8BIT`) whatever the stream's
encoding, while the read-to-end-of-file `IO#read` this replaced returned the
external encoding. `.reencode` puts that encoding back, so the size caps
introduced by the drain rewrite are the only visible change here and
`Sway::Utf8.scrub` still sees what it used to.

## See also

- `docs/explanation/subprocess-bounded-execution.md` — why this module
  exists at all.
- `docs/explanation/subprocess-deadline-design.md` — the wall-clock
  deadline that output draining shares with child exit.
- `docs/explanation/subprocess-termination-and-pid-reuse.md` — how a
  reader's overflow kill and the deadline's own kill both reach the right
  process group.
