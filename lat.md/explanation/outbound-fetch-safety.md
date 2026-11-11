---
lat:
  mode: explanation
---
# Fetching from somewhere else

Sway downloads PDFs, images and a law corpus from hosts it does not control, and every one of those requests can be aimed somewhere unintended or made larger than the machine can hold.

## Every redirect hop is checked before it is followed

A public host can answer with a 302 to a private address, so a redirect is walked by hand and each hop is checked against the allowlist before anything is requested.

Letting the HTTP library follow redirects itself is what made that reachable:
the check ran on the address Sway asked for and not on the address it ended up
at, so one redirect was enough to reach Sway's own network. The Legistar
connection carries no redirect-following middleware for the same reason — with
one installed, every hop would bypass the check.

## An oversized download is stopped rather than refused afterwards

A cap enforced after the body is in memory has already cost the memory it was meant to save, so the read stops at the cap instead.

`BoundedResponseBody` turns "refuse an oversized download afterwards" into
"stop reading it", which is why the examples measure the bytes actually held
rather than the value finally returned: a check made after the fact passes while
still holding the whole body.

The law corpus is the same story one layer up. That service used to read the
tarball fully into memory and gzip-expand it with no bound on either number,
while every sibling download path capped both. It now takes the archive a chunk
at a time, which is a shape a double returning one in-memory string cannot
express — so the examples build a real streaming response.

## A declared size is checked as well as the bytes that arrive

Headers claiming more than the cap are refused even when the bytes that actually arrive would fit inside it.

The running byte count cannot see that case: it stops a body that grows past the
cap, and a truthful header on a small body never trips it. Checking the declared
length first also refuses a sender that promises far more than it delivers,
which is the cheap half of the same defence.

## A dropped connection is retried where repeating is safe

The retry list on the GET profiles includes connection resets and a TLS read cut short, not only timeouts.

The library's built-in exception list covers timeouts alone, so a single SSL
error was never retried and killed whole runs. Repeating a GET is safe, which is
what makes the wider list acceptable there and not elsewhere.
