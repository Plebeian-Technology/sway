---
mode: explanation
summary: "Explains why BoundedResponseBody hooks Faraday's on_data instead of checking response.body afterwards, why a redirect body is counted but dropped, and why a backwards running total signals a retry restart."
status: agent-extracted
related: []
---
<!-- vale Vale.Spelling = NO -->

# Why BoundedResponseBody is built the way it is

`BoundedResponseBody` collects a response body AS IT ARRIVES, and refuses
it the moment it passes a byte cap.

## Why it exists

Faraday's default setup reads the whole response into a string before any
of Sway's code runs, so a size check written afterwards measures something
the machine is already holding. On a single Raspberry Pi that is the only
bound that matters: the checks downstream (what gets written to disk,
handed to mutool, stored in a column) all act on a value memory has
already paid for. Handing Faraday one of these as its `on_data` handler is
what turns "refuse it afterwards" into "stop reading".

## Why a redirect's body is counted but dropped

Not every response is the payload. A redirect's body is a courtesy page
nobody reads, and failing an attachment because the server put a large
one in front of it would be a new way to lose a document rather than a
safeguard. Those bytes are counted and dropped: `keep: false` holds
nothing and raises nothing, so memory stays flat however big the page is.

## Why a backwards-moving total is the retry signal

`faraday-retry` re-runs the whole request, and the running total Faraday
passes is per attempt — so a second attempt begins again at the size of
its first chunk. Without noticing that, the buffer would hold attempt
one's bytes with attempt two's appended, and the caller would get a body
that is neither. A total that has gone backwards is the signal, and it is
the only one available here.

## Why TooLarge is its own class, not the caller's

`TooLarge` is raised as soon as the running total passes the cap. It is
deliberately its own class rather than the caller's: this object knows the
number, not what the download is for. `Legistar::AttachmentFetch` and
`FetchLawCorpusService` each turn it into the `TooLarge` their own callers
already rescue.
