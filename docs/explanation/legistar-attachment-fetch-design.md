---
mode: explanation
summary: "Explains why Legistar::AttachmentFetch owns the allowlist check, the redirect walk, and the size cap together, and the streaming/error-translation details that keep each one honest."
status: agent-extracted
related: [docs/explanation/legistar-attachment-url-allowlist.md, docs/explanation/attachment-fetch-safety-checks.md, docs/explanation/legistar-client-design.md]
---
<!-- vale Vale.Spelling = NO -->

# Legistar::AttachmentFetch design notes

`Legistar::AttachmentFetch` is the one place an attachment PDF gets
downloaded. See [Why bill PDF downloads go through a shared fetch
class](attachment-fetch-safety-checks.md) for why callers route through it
at all. This document covers the class's own internals: why its three jobs
have to stay together, and the implementation details that keep each one
honest.

## Why the allowlist, the redirect walk, and the size cap live in one class

They own three things that must never be split apart:

1. `Legistar::AttachmentUrl`'s scheme/host allowlist, checked on the first
   url AND on every redirect target.
2. A redirect walk with a hard hop limit, done step by step in plain sight.
3. A size cap on the final response.

`Sway::FaradayStack.legistar` deliberately mounts no `follow_redirects`
middleware: it follows Location headers invisibly, so an allowlist at the
call site would see only the first url. One upstream 302 could then steer
the request at any server never approved — server-side request forgery, an
outsider using our server to make requests on their behalf.

Walking the chain by hand here is the same shape
`ExternalAssetMirrorService#resolve_final_url` already uses for the same
risk.

Transport errors are NOT rescued here — the caller decides how to degrade
per attachment or per bill, and already rescues `Faraday::Error`.

## Why MAX_REDIRECTS is 3

Three hops covers a CDN hop plus an auth hop with room to spare. Following
redirects forever would let a redirect loop tie up our single Raspberry Pi
server — a denial of service.

## Normalizing the url once, before either the allowlist or the request sees it

`#call` normalizes the url ONCE, at the top, and uses the normalized value
for both the allowlist check and the request. This used to hand Faraday the
raw string while the allowlist judged a trimmed copy — a whitespace-padded
attachment link would PASS the allowlist and then raise
`URI::InvalidURIError` inside the transport, validator and transport
disagreeing about what the url even is.

`AttachmentUrl.normalize` is used rather than a hand-written `.strip`, so
there is one definition of that agreement instead of a copy per call site.
It also scrubs invalid UTF-8, which a bare strip raises on.

The `rescue URI::Error` around the whole redirect loop is a backstop, not a
live path: nothing that passes `reject_disallowed!` should reach it, since
the allowlist parses the same trimmed string. It decides whether the next
unparseable url costs one attachment or the whole run, and keeps the
promised set of raised errors to exactly `Rejected` and `Faraday::Error`.

## Why the size cap is applied while bytes arrive, not after

`#get_bounded` reads the request a chunk at a time, so nothing oversized is
ever fully in memory.

THE CAP USED TO BE APPLIED AFTER THE FACT, and a comment here used to claim
it bounded memory. It did not: Faraday's default setup reads the whole body
into `response.body` before our code runs. Measuring it afterwards
described a string the machine was already holding, for every response.
The retry profile makes up to three attempts, so one attachment could
buffer several whole bodies.

Setting `on_data` moves the check to where bytes arrive. Faraday hands each
chunk to the handler and stops building its own body, so the buffer built
in `BoundedResponseBody` IS the body, written back onto the response.

`keep:` preserves the older rule that a redirect's body is not the payload.
Faraday supplies the status alongside each chunk, so a 3xx's bytes are
counted and dropped rather than refused.

## Why the advertised Content-Length is still checked separately

`#enforce_advertised_size!` is the one check the running bound cannot make:
a server that says up front it is about to send more than the cap.
Refusing on the header costs nothing and names the number the server gave.

It also covers a server that ADVERTISES more than it sends. The bytes are
then within the cap and the running check never fires, so without this
check an oversized-header response would be accepted.

The matching post-hoc check on the actual size is GONE, not overlooked: a
body assembled by `BoundedResponseBody` cannot exceed the cap, so a second
check after the fact would be a line that never runs.

## Why #absolute_target rescues URI::Error, not just URI::InvalidURIError

`URI::BadURIError` and `URI::InvalidComponentError` are siblings of
`URI::InvalidURIError`, not subclasses, so catching only the one would miss
the others. This is the only thing standing between a malformed Location
header and the run-killing escalation the redirect-loop backstop above
exists to prevent.

## MAX_ATTACHMENT_BYTES: how the 32 MB cap was sized

The download size limit lives here because both download paths go through
this class, and previously only one checked size. The 30s timeout bounds
TIME; this bounds SIZE, and now MEMORY too.

The number comes from real observed data: the largest genuine testimony
file seen is the 12.4 MB bundle at
`FetchBillsService#select_primary_attachment`. 32 MB is about 2.5x that —
roomy enough that no real hearing bundle is refused, tight enough that a
hostile upstream can't exhaust the Pi's memory. A cut-off PDF isn't usable,
so the whole response is refused rather than trimmed.
