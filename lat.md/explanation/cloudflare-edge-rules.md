---
lat:
  mode: explanation
---

# Cloudflare edge rules

Cloudflare stands in front of every request to sway.vote and answers some of them itself, so those requests never reach Rails. That configuration lives in Cloudflare, not in this repository.

## What the edge answers

Firewall rules, a rate limit, Cloudflare's managed rulesets and its bot
protection can each end a request before it crosses the tunnel. A request
ended there leaves no Rails log line and no application error report.

Those rules target traffic Sway never serves — probes for PHP applications,
WordPress, leaked configuration files and exposed source-control folders, and
methods other than GET and OPTIONS at the site root, which Rails answers with
one GET. Ordinary use, including the fifteen-second and five-second polling on
user-facing and admin pages, stays well inside the rate limit.

## Redirect rules

Redirect rules on the edge answer some requests with a 301 before Rails sees
them. Two of them exist only because Firefox cannot use a passkey across
related origins, and Sway's passkeys are bound to the relying-party id
`app.sway.vote`.

- Firefox on the apex, the www name or the short bill hostname is sent to
  `app.sway.vote`, so a passkey ceremony runs on the origin the credential is
  bound to. The redirect excludes `/.well-known/`, which keeps the
  associated-domain documents on the apex host, where Android reads them
  ([[android-app-links]]).
- Other browsers on the short bill hostname go to `sway.vote/bill_of_the_week` (the retired name, which Rails redirects to `/bill_of_the_month`),
  and the www name goes to the apex.

The `app.sway.vote` name stays whatever Firefox later supports, because a
credential already enrolled is bound to it ([[identity-and-access]]).

## When a request never reaches Rails

A request that leaves no Rails log line may have ended at the edge, and nothing
in this repository would show that.

The Security Events view in the Cloudflare dashboard is where such a request
appears, named with the rule that ended it. It is the first place to look when
a client reports an error that Rails never logged.
