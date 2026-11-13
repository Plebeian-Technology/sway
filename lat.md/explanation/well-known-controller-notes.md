---
lat:
  mode: explanation
---

# WellKnownController design notes

This controller serves the WebAuthn "related origin requests" file and the mobile app-link files (Apple's AASA, Android's assetlinks.json).

Background: [web.dev: WebAuthn related origin requests](https://web.dev/articles/webauthn-related-origin-requests).

## Why both hosts are authoritative

The mobile app's `linking.ts` targets BOTH the bare domain and the `app.` host, and Apple and Google look for the association files on the EXACT host the app claims.

So every host the app claims must be listed in the association hosts setting ([[well-known-controller-notes#Why the served hosts are configuration]]). The production reverse proxy (Caddy / Cloudflare tunnel) MUST forward `.well-known/*` on each of those hosts to Rails — see the launch checklist.

## Why the served hosts are configuration

The hosts that answer the association files and the WebAuthn related-origin file are an instance's own domain names, so they are settings, not code: [[lib/sway/settings/mobile.rb#Mobile|`APP_ASSOCIATION_HOSTS`]] and [[lib/sway/settings/webauthn.rb#Webauthn|`WEBAUTHN_RELATED_HOSTS`]].

Each is a comma-separated list read through the array caster and compacted on load like the fingerprint list ([[settings-groups#Why the fingerprint list is compacted on load]]). Neither has a default naming a real domain: unset reads as an empty list, and an empty list makes every host answer the way an unknown host always has — `204 No Content`. A fork that sets nothing therefore publishes no claim on anyone's domain.

Production renders both from `RAILS_ALLOWED_HOSTS` in `config/deploy.yml`, keeping only the names and dropping IP addresses and anything carrying a port. Host authorization already refuses any request whose host is not on that list, so these lists could never usefully hold a name outside it; deriving them keeps one place to change when a domain is added. A name that looks like an address would publish nothing Apple, Google or a browser can use.

Development needs no entry for the tunnel: the dev tunnel host is appended on its own ([[well-known-controller-notes#Why the dev tunnel host is appended only in development]]), so the two settings name only extra hosts a contributor wants to test against.

## Why the related origins are the related hosts

`/.well-known/webauthn` lists `https://` plus each host that serves it, rather than a separately configured origin list.

One list cannot drift from the other, and every host that serves the file is a host a passkey ceremony may legitimately start on. The list used to be a hand-kept subset of the serving hosts; the only production difference is that the `www.` origin is now listed too, which the WebAuthn allowed-origins fallback already accepts.

## Why the dev tunnel host is appended only in development

A contributor running their own Cloudflare tunnel serves the app from a host the configured lists cannot know in advance, and Apple/Google require the association files on the EXACT claimed host.

`dev_tunnel_host` returns `nil` unless `Rails.env.development?`, so this is development-only: production must never widen its host allowlist from an environment variable.

## Why the AASA paths list is tested against the real route table

Every pattern in `#aasa`'s `paths` list has to match a real Rails route, or iOS keeps handing that address to the browser and nothing anywhere reports it.

`well_known_spec` walks this list against the route table with `recognize_path`, which resolves controller routes only, so the retired `/bill_of_the_week` path (a 301 redirect route) is exempted by name. It must be kept in step with `mobile/src/navigation/linking.ts` and the Android intent filters in `mobile/app.config.ts`.

## Why the request spec compares against Android's list, not just asserts it

Android's assetlinks carried its own, shorter path list than iOS's AASA, so a membership link opened the app on iPhone and the browser on Android — and a code comment claimed the two lists matched when they did not.

`spec/requests/well_known_spec.rb` compares the two lists directly rather than asserting each in isolation, because comparing them is the only thing that actually keeps that claim true.

## Mobile: deepLinkPatterns.ts

`mobile/src/navigation/deepLinkPatterns.ts` lists the addresses this app claims, in Apple's wording, because Rails serves exactly this list at `/.well-known/apple-app-site-association`.

A spec compares the two, so changing one without the other fails.

A hyphenated `/bill-of-the-week` matched nothing for months: the Rails route is underscored.

Android matches a path by prefix, by exact value, or by a limited pattern — never by Apple's glob, so each one has to be translated (`androidPathData`):

A prefix is only usable when the trailing `*` is the ONLY one. Reaching for it whenever a pattern merely ENDS in `/*` turned `/organizations/*/memberships/*` into the prefix `/organizations/*/memberships`, which no real address begins with — so the membership link stayed broken on Android, which is the whole thing this fix set out to repair.

The trailing slash is KEPT. Apple needs a character after it, so `/bills/*` leaves the bills list to the browser; an Android prefix is a plain string prefix, so dropping the slash claims `/bills` and `/billsomething` as well and the two platforms disagree again.

## Mobile: linking.ts

`mobile/src/navigation/linking.ts` says which web addresses open which screen in the app.

The list of prefixes must contain both `https://sway.vote` and `https://app.sway.vote`. Apple and Google only hand a link to the app if the exact host serves the small proof-of-ownership file they look for, and Rails serves that file on both hosts. Any address on either host that matches a path below opens the app instead of a browser. The `sway://` scheme keeps working too, for links used inside the app itself.

`DEEP_LINK_PATTERNS` is the claimed list. Rails serves it in the ownership file, and a web link to anything else here opens the browser however well the app could answer it. The claimed paths are:

- `bills/:id` — a bill's detail. It is registered in both the Home and
  Bills stacks, so the link opens inside whichever section the reader was
  already in.
- `bills` — the All Bills list
- `past_bills_of_the_month` — the Past Bills of the Month list
- `legislators/:id` — a legislator's detail
- `legislators` — the legislators list
- `bill_of_the_month` / `bill_of_the_week` — the Bill of the Month, and its retired name, which
  redirects there so old links still open the app. Underscored, because that is the Rails route;
  a hyphen here matched no address at all.
- `organizations/:orgId/memberships/:id` — one membership
- `organizations/:id` — an organization's detail
- `organizations` — the organizations list

The `bills/:id` entry parses its id with `Number`, so a link's id reaches the bill screen as a number. A value that is not a positive integer, such as `..%2Fsomething`, shows the bill screen's empty state and never requests a path under `/bills/`. See [[mobile-bill-detail-and-bill-of-the-month-screens#BillDetailScreen and BillOfTheMonthScreen#Loading and error states]].

`feed`, `profile`, `sign-in`, and `users/organization_memberships` (the memberships list) stay unclaimed on purpose: each shows something that differs by who is signed in. A public page reads the same for everyone, so opening it in the app is simply better; a personal page does not — a web link that opens the app on a sign-in wall is worse than a browser page that shows the reader why. Those four answer `sway://` links from inside the app only.

### Why androidPathData must never hand back a prefix containing a star

A prefix carrying a literal star is the failure case above happening again: it reads as a working translation rule and matches nothing.

## deepLinkPatterns.test.ts: the third link in the deep-link chain

Rails and the phone agree on the list (above), and the list translates correctly into Android's wording (`androidPathData`, above) — and both of those can be true of an address no screen answers.

Then the app opens to nothing, which reads to a person as the app being broken rather than the link being unclaimed. `mobile/__tests__/navigation/deepLinkPatterns.test.ts` adds that third check: every pattern in `DEEP_LINK_PATTERNS` has to match a route `linking.config` actually serves. `/bills/*` and `bills/:id` are the same address written two ways: one segment at a time, a literal must match and a wildcard answers a name. Unanswered patterns are collected rather than asserted one at a time, since Jest's `expect` takes no message, so an empty list is what puts the offending address in the failure.
