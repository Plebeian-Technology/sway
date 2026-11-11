---
mode: explanation
summary: "Explains why bill PDF downloads are routed through a shared fetch class that enforces a host allowlist and a response size limit."
status: agent-extracted
related: []
---
# Why bill PDF downloads go through a shared fetch class

<!-- vale Vale.Spelling = NO -->

Why `FetchBillsService#download_pdf` hands the PDF URL to
`Legistar::AttachmentFetch` instead of fetching it directly, and why that
class carries both a host allowlist and a response size limit.

## One shared seam for the host allowlist

`FetchBillsService#download_pdf` and `FetchHearingsService#download_attachments!`
both hand a full URL, chosen upstream by Legistar, to
`Legistar::AttachmentFetch#call`. That class is the shared seam where the
host allowlist and the size limit live — neither service reads the response
body directly.

Comments in both call sites used to name a `conn.get(pdf_url)` call. That
call has not existed since the fetch moved behind
`Legistar::AttachmentFetch`; someone grepping for it to audit the allowlist
would have found nothing and wrongly concluded there was no check at all.

If the fetched URL redirects, that is treated as no PDF found — a redirect
is quietly recorded the same way a missing attachment would be, rather than
being followed and trusted.

Far fewer requests happen at the bill-PDF site than at the hearings site —
one attachment per bill, versus up to 200 for hearings — but the allowlist
check has to exist in both places anyway, or it is only a suggestion rather
than an actual guarantee. `Faraday::Error` still travels up to each
caller's existing rescue; `Legistar::AttachmentFetch` does not swallow
network errors, only the checks it owns.

## The same argument applies to the size limit

`FetchBillsService#download_pdf` used to read `response.body` and write it
out to disk with no size limit at all. Whatever gets written there is what
`mutool` — and, for a scanned document, a 300-DPI image render plus
`tesseract` run on every page — then has to process, on the single
production Raspberry Pi.

The size limit now lives on `Legistar::AttachmentFetch`, next to the host
allowlist, rather than at each call site. A response body over the limit
arrives at the caller as `Legistar::AttachmentFetch::TooLarge`, which is a
subclass of `Legistar::AttachmentFetch::Rejected` — so the existing
`rescue Legistar::AttachmentFetch::Rejected` in `#download_pdf` already
covers it without any extra rescue clause.

## Why the download seam is separate from the API client seam

`FetchHearingsService#attachment_fetch` (wrapping
`Legistar::AttachmentFetch`) is kept separate from `#legistar_client`
(wrapping `Legistar::Client`) because the two build URLs differently: the
API seam builds RELATIVE paths under the connection's `url_prefix`, while
an attachment hyperlink is an ABSOLUTE url that overrides it — which is
exactly why the download seam needs a host allowlist and the API seam does
not.

## Why the Legistar Faraday connection does not auto-follow redirects

`Sway::FaradayStack.legistar` (`lib/sway/faraday_stack.rb`) builds the
connection `Legistar::AttachmentFetch` fetches over, and deliberately does
not mount `conn.response(:follow_redirects)`, unlike `.github`.

Attachment bodies are fetched over that connection from an ABSOLUTE url the
upstream supplies, and the `follow_redirects` middleware follows `Location`
headers invisibly — a host allowlist applied at the call site would only
ever see the first hop, so a single upstream 302 would reopen the SSRF hole
(tricking the server into fetching an attacker-chosen URL) that
`Legistar::AttachmentUrl` closes. Redirects on attachment downloads ARE
followed — explicitly, re-checking every hop — by `Legistar::AttachmentFetch`
itself. Adding the middleware to the connection would remove that guarantee.

## `#download_attachments!` isolates failure per record

`FetchHearingsService#download_attachments!` downloads every PENDING
candidate straight over the injected Faraday connection. A record discovery
already marked "failed" is left alone. Every failure path changes ONLY the
record being worked on and never raises, so one bad attachment can never
fail the bill or the stage.

## Why the filename is cleaned again at the write itself

`FetchBillsService#download_pdf` runs `pdf_filename` through
`Legislation::Paths.upstream_file_name` a second time, even though its only
caller already cleaned it once. The write call is the line that actually
names a file on disk, so it does not take the caller's cleaning on trust —
a future call site that forgets to clean its filename first still cannot
write outside the artifact root.
